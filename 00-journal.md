This file serves as a detailed step-by-step journal of what I have done to resolve the assessment.

## 1. Assessment Analysis

### 1.1 Business Domain and Tech Stack

The assessment asks us to design a core data layer for fintech payments. This raises 2 issues for me: (1) I do not have experience with fintech and its terminology, and (2) the main tech stack is PostgreSQL, which we are studying, and it is not my main experience stack.

To cover our weaknesses here, we will utilize AI to help with the missing pieces. Then we will apply our previous knowledge about customer asset systems to resolve the given problem.

### 1.2. First impression

#### The transaction table
The transaction table has 50 million rows and receives an additional 2 million rows per month.

So we have about 24 months of data in the table. The context mentions that the query on the table is slow in production. Let's make some blind guesses here:
- There is no DDL provided, so we cannot pinpoint whether the table has indexes or not. For a production table, it should have indexes, so we need to guess which indexes are applied here.
- One of the biggest performance killers is a table scan without using an index, so if the query scans 50 million rows and then filters for 2 million rows to compute, this can be the problem.
- The query is an aggregate query, which means even though the number of rows returned is small (in this case the number of wallets), the query always needs to scan 2 million rows in order to compute the final result.

If this were SQL Server, we would have some solutions that could resolve the issue:
- The point of the query is to calculate the statement for all wallets that have been settled in a month. For historical data, the number rarely changes, so it is safe to pre-aggregate the result beforehand and save it into a set of reporting tables. We can then redirect the query to those tables.
- 24 months of data is very large, and should not be treated the same. In our previous system, we split the table into 2 physical ones. The first is a hot/live transaction table, prone to updates and with a large amount of DML. The second is an archived transaction table, where we move data if the data is older than a specified amount. Depending on the load, the time varies from 3 days to 1 or 2 months. For this example, we can safely serve a few million rows. And for the running month and previous month calculation, let's make it 2 months. The other 22 months will be saved inside an archived table for easier maintenance and tuning. (the live table and archived table have different index strategies). This also helps reduce our backup size on the main database, which is very important.

But we will use PostgreSQL for our assessment, so the insights above can be applied, but must be adjusted to adapt to PostgreSQL.

One of the biggest differences between SQL Server and PostgreSQL is the MVCC model of PostgreSQL. This model does not modify tuples in place; it instead creates a new tuple and updates the pointer to it. Because of this, there are no clustered indexes in PostgreSQL either. So we cannot use a clustered index strategy here.

PostgreSQL index scans also have a different mechanism here. Because multiple records of a tuple can exist, an index must fetch the data page to ensure it has the latest data value. This can be mitigated by ensuring the page is clean via fillfactor and the vacuum process. If we can ensure the page is clean, PostgreSQL can use an index-only scan to speed up the query.

The query pattern is an exact match on status and a range scan on created_at. Usually, index strategy follows exact, sort, scan priority. But in this case, we can argue that the status is mostly settled if we account for 1 month. So indexing status has limited benefit here. We also have group by wallet_id, which is sorting heavy. And finally, we have currency, which is a design problem. If currency is an attribute of wallet, we should not add it to group_by, instead we should use an aggregate in SELECT because for 1 wallet, currency is the same. But if we have multiple currencies in a wallet, the key here is composite and it makes the query harder. This will reflect in my core design later. I will lean toward keeping currency as an attribute.

So if we must use an index to improve our query, here are some options (the INCLUDE is optional, we need to test if index-only scan works or not):
- IX(wallet_id, created_at) INCLUDE (status, amount, currency) : This pattern works for customer-facing dashboards, because queries for customers always have wallet_id, so reporting every month is a trivial scan. But our query here focuses on summary by month for all wallets, so it will be hard for the planner to emit a plan that can utilize this index pattern. We can rewrite by selecting unique wallet_id, then joining with transactions to force the plan. But because PostgreSQL planning will focus on column statistics, the result might vary. In SQL Server, we have another problem where this query is a nested loop, which is a performance killer in some cases (not sure how the query plan in PostgreSQL will treat this).
- IX(created_at) INCLUDE (wallet_id, status, amount, currency) : This pattern focuses on the chronological order of transactions. This is an audit-centric pattern. But for our reporting query, this index will cover the exact number of records needed for the query, but wallet_id will then be useless in the key and will need to be sorted anyway, which is costly. I will refrain from using this unless necessary because the cost-benefit might not be good here. This also needs thorough testing. The reason wallet_id is not put in the index key is because created_at has seconds/milliseconds accuracy, so it always needs to be sorted again for group by. This is the main reason why we usually have different summary tables that pre-aggregate by year/month/day/hour for reporting purposes. I will lean into this solution more than using the index.
- Partition(created_at) & IX(wallet_id) : This is the best pattern because a range query by month will only touch the needed partition, including the index, so we can have the best of both worlds here: range query for only needed tuples + pre-order on wallet_id to skip sorting entirely. This also enables further management best practices using partitions.

#### Core model

The goal for this assessment is to expand from the transactions table as the entry point and deliver a full schema for the payment domain. This is a new domain for me, so I need to study to get the correct business understanding before continuing.

I can recognize most of the terms here, except the **double-entry ledger**. So I will use AI to run research on this topic so that we can have a deep understanding of this entity to design the best schema for it.

Delivery artifacts for this task are ERD and DDL in SQL format. I already have a way to visualize the ERD with the help of AI, so I will reuse it. SQL files also need to be executable so we can validate the schema. If we have time, we can use AI to generate a generator service that mimics the backend so we can have data in these tables for validation.

We already did a bit of the extra reasoning requirement when analyzing the transaction table; we can bring that over here.

#### Query & performance

Because we don't have much experience in PostgreSQL, the analysis in this section needs extra work so that I can understand how PostgreSQL planning works. This requires data to experiment with. We only have 2 days left, so we need to work fast here. AI can help, but I am not sure we can get it done in time, so we need to have some delivery artifacts first; deep analysis comes later.

#### Zero-downtime migration

This task introduces a new NOT NULL column, `settlement_batch_id`, and it needs to be updated live. The goal is to have zero-downtime deployment. Actually, the column name is just an example, so I can assume this task only cares about deployment planning. So I can safely skip the business aspect of the column and focus on deployment steps only.

With the above assumption in mind, the task becomes creating a base script for deployment and some basic business requirements for the value (because NOT NULL), so that we can populate data (backfill) for this new column.

Live deployment with zero downtime needs extra care around the internal workings of PostgreSQL. Some of the most important items are: locking, long-running queries, vacuum process, fillfactor, transaction commits and rollbacks.

Like always, we need to control the state of deployment via each step. MongoDB is a bit easier since the schema is flexible. PostgreSQL needs extra care in DDL, so keep that in mind.

One of the items we need to explain is the application point of view. The deployment step needs extra care so it does not break the old version of the application. Usually, I want database deployment to be as independent as possible. So the best way is to have a 3-stage deployment: (1) introduce the new column without a constraint; (2) deploy the application that will populate data into the new column without showing new changes yet (this can be a transitioning version or a feature flag that is turned off; I prefer the second); (3) backfill data and enforce the constraint before turning on the feature flag (or deploying the final application). This needs extra collaboration with the application side, so we might need another plan in case the above assumption is wrong.

#### Polyglot modelling

The task is to expand data modelling into other DBMSs. I have experience in MongoDB, so that part is easy. Neo4j needs some understanding of graph theory, which I lack a bit. But the core concept is still the same: the best tool for the job.

For MongoDB, its strongest points are the dynamic schema approach and document-centric design. With its self-developed physical data representation, BSON, MongoDB makes good use of document storage and the aggregation framework. One other strong point that most people miss is that MongoDB has a built-in HA solution, which most RDBMSs lack, so it is not only about the data modeling aspect; some administrative considerations must be assessed too, but this is outside of the task, so I will skip it. Most people use MongoDB to store logs only. This is understandable because logs are very schema-volatile, so the flexible schema approach is best used here. Also for auditing purposes, compliance usually requires the underlying data to be immutable. MongoDB has capped collections that forbid all updates on the collection. Even the root account cannot modify the data without dropping and repopulating data, so storing audit data in MongoDB has this advantage too. The latest MongoDB has time series collections and clustered collections, so if we have data that requires these features, we can consider using MongoDB.

For Neo4j, the best use for it is, of course, graph problems such as relationship mapping or fraud detection. I lack some basic knowledge about real-world graph problems, so I need to run some research for it too.

#### Observability

For the monitoring aspect, we must approach it from 2 aspects: technical and business.

For the technical side, all basic metrics related to PostgreSQL and its performance need to be captured. So we start with basic metrics for all DBMSs: CPU, memory, I/O, internal logs (for PostgreSQL: WAL logs), locking/waiting, connections, cache hits/misses, and index utilization. Then focus on PostgreSQL-specific metrics: vacuum, dead tuples, and transaction IDs.

For the business side, we need to monitor query and procedure duration, especially around core business flows. But for this aspect, we don't have much context, so this needs more thought later.

#### Design write-up

Our analysis can cover most of the ADR here, but the task requires some more thought about standards and the microservices aspect, so I need to cover them too.

#### Tools

- I am very familiar with MongoDB and Grafana.
- I am not as familiar with PostgreSQL and Neo4j since I have not had the chance to actually maintain those services in production yet, but I have some knowledge about them; so I need to study more.
- About Flyway and Liquibase, I have no idea, so my approach will be ad hoc scripts first, then have AI do some search for me about these systems to see if I can grasp the gist of these systems or not.

### 1.3. Journal audit / feedback

The audit shows my lack of knowledge of PostgreSQL. This is good, it gives me a pointer on how to address my gap here. Most of the clarification is for things I already know or awareness of what I lack. Some of it is kind of a misunderstanding because my thought wording is not clear enough, not that I do not know about that part, but I kind of forgot to include it in the thought. It's good to know how to clarify the thought. The final part is what the AI already assumes, like settlement; I will ignore this because of my lack of domain knowledge and stick to the technical aspect of the task. Lack of knowledge is not a bad thing; relying on AI for what I don't know is bad.
