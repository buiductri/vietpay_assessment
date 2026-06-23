This file is served as details step journal i have taken to resolve the assessment

## 1. Assessment Analysis

### 1.1 Business Domain and Tech Stack

The assessment ask for designing a core data layer for fintech payment, this raises 2 issues for me: (1) I do not have experience with fintech and its language term, (2) the main tech stack are PostgreSQL, which we are studying, not main experience tech stack.

To cover our weakness here, we will ultilize AI to help with missing pieces. Then apply our previous knowledge about customer assets system to resolve the given problem.

### 1.2. First impression

#### The transaction table
The transaction table is 50 mil rows and having additional 2 mil rows per month.

So we have about 24 months of data in the table. The context mention that the query on the table is slow in production. Let's made some blind guess here:
- There is no DDL provided, so we cannot pinpoint if the table have index or not. For production table, it should have, so we need to guess which index are applied here.
- One of the most performance killer is table scan without using index, so if the query scan for 50 mil rows then filter for 2 mil rows to compute, this can be the problem.
- The query is an aggregate query, which means even though the number of rows returned is small (in this case the number of wallets), the query always need to scan 2 mil rows in order to compute the final result.

If this is SQL Server, we have some solutions that can resolve the issue:
- The point of the query is to calculate the statement of all wallets that have been settled in a month. For historical data, the number rarely changes, so it is safe to pre-aggregate the result beforehand and save into a set of reporting tables. We can then redirect query to those tables.
- 24 months of data is very large, and should not be treated the same. In our previous system, we split the table into 2 physical one. The first is hot/live transaction table, prone to update and have large amount of DML. The second is archived transaction, which we moved data into if the data is older than a specificed amount. Depend on the load, the time varied from 3 days to 1 or 2 months. For this example, we can safely serve a few millions of rows. And for running month and previous month calculation, lets make it 2 months. The other 22 months will be saved inside an archived table for easier maintenance and tuning. (live table vs archived table have different index strategy). This also help reduce our backup size on main database, which is very important.

But we will use PostgreSQL for our assessment, therefore above insight can be apply, but must be adjusted to adapt to PostgreSQL.

One of the bigest difference between SQL Server and PostgreSQL is the MVCC model of PostgreSQL. This model does not modify tuple in place, it instead creates new tuple and update pointer to it. Because of this, there are no cluster index in PostgreSQL neither. So we cannot use clustered index strategy here.

PostgreSQL index scan also have different mechanism here. Because there are multiple records of a tuple exists. Index must fetch data page to ensure latest data value. This can be mitigated by ensure the page is clean via fillfactor and vacuum process. If we can ensure the page is clean, PostgreSQL can use index only scan to speedup the query.

The query pattern is exact match on status and range scan on created_at. Usually, index strategy prefer exact - sort - scan priority. But in this case, we can argue that the status mostly in settled status if we account for 1 mounth. So indexing status have limited benefit here. We also have group by wallet_id, which is sorting heavy. And finally, we have currency, this is a design problem. If currency is an attribute of wallet, we should not add it to group_by, instead use aggregate on SELECT because for 1 wallet, currency is the same. But if we have multiple currency in a wallet, the key here is composite and it make query harder. This will reflect in my core design later. I will lean into keep currency as an attribute.

So if we must use index to improve our query, here are some options (the include is optional, we need to test if index only scan working or not):
- IX(wallet_id, created_at) INCLUDE (status, amount, currency) : This pattern works for customer facing dashboard, because query for customer always have wallet_id, so reporting every month is trivial scan. But our query here is focusing on summary by month for all wallets, so it will be hard for the plan to emit a plan what can ultilize this index pattern. We can rewrite by SELECT unique wallet_id then JOIN with transactions to force the plan. But because PostgreSQL planning will focus on column statistics, the result might vary. In SQL Server we have other problem that this query is nested loop, which is performance killer in some case (not sure how query plan in PostgreSQL will treat this).
- IX(created_at) INCLUDE (wallet_id, status, amount, currency) : This pattern is focusing on chronological order of transactions. This is audit centric pattern. But for our reporing query, this index will cover exact number of records needed for query, but wallet_id then will be useless in key and need to be sorting anyway, which costly. I will refrain from using this if neccessary because the cost-benefit might not be good here. Also need thorough testing to ensure. The reason wallet_id not put in the index key is because created_at is seconds/milliseconds accuracy, so it always need to be sorted again for group by. This is the main reason why we usually have different summary tables that pre-aggreate by year/month/day/hour for reporting purpose. I will lean into this solution more than using the index.
- Partition(created_at) & IX(wallet_id) : This is the best pattern because range query by month will only touch needed partition, including index, so we can have the best of both worlds here: range query for only needed tuple + pre-order on wallet_id to skip sort entirely. This also enable futher management best practice using partition.

#### Core model

The goal for this assessment is to expand the entrypoint at transactions table and deliver a full schema for payment domain. This is new domain for me so need to study for correct business understanding before continue.

I can recognise most of the term here, except the **double-entry ledger**. So I will use AI to run a research on this topic so that we can have deep understanding of this entity for designing the best schema for it.

Delivery artifact for this task is ERD and DDL in SQL format. I already have a way to visualize the ERD with the help of AI so I will reuse them. SQL files also need to be executable so we can validate the schema. If we have time, we can use AI to generate a generator service that mimic the backend so we can have data in these tables for validation.

The extra reasoning requirement we done a bit when analyze the transaction table, we can bring them over here.

#### Query & performance

Because of we don't have much experience in PostgreSQL, so the analysis in this section need extra work so that I can understand how PostgreSQL planning works. This require data to experiment. We only have 2 days left, so need to work fast here, AI can help but not sure we can done it in time so need to have some delivery artifacts first, deep analysis comes later.

#### Zero-downtime migration

This task introduces new column `settlement_batch_id`, NOT NULL and need to be update live. The goal is have zero-downtime deployment. Actually, the column name is just an example so I can assume this task only care about deployment planning. So I can safely skip business aspect of the column and focus on deployment step only.

With above assumtion in mind, the task becomes having a base script for deployment, some basic business requirement for value (because NOT NULL), so that we can populate data (backfill) for this new column.

Live deployment with zero downtime need to have extra care about internal working of PostgreSQL. Some of the most important items are: locking, long running query, vacuum process, fillfactor, transaction commit & rollback.

Like always, we need to control the state of deployment via each steps. MongoDB is a bit easier since the schema is flexible. PostgreSQL need extra care in DDL, so keep that in mind.

One of the item we need to explain is application point of view. The deployment step need to be extra care that do not break the old version application. Usually, I want database deployment to be as independent as possible. So the best way is to have 3 stage deployment: (1) introduce new column without constaint; (2) application deployment that will populate data into new column, the best way is not have application show new changes yet (this can be a transitioning version or feature flag that turn off, prefer second); (3) backfilling data and enforce constraint before turn on flag feature (or deploy final application). This need extra collaboration with application side so we might need other plan in case of above assumtion is wrong.

#### Polygot modelling

The task is to expand data modelling into other DBMS. I have experience in MongoDB so that part is easy. But Neo4j need some understanding in graph theory, which I a bit lack. But the core concept still the same: best tool for the job.

For MongoDB, its best strong point is the dynamic schema approach and document centric. With self developed physical data representation BSON, MongoDB take the ultilization to the best via document storage and aggregation framework. One of other strong point that most people missed is that MongoDB have builtin HA solution, which most RDBMS miss, so not only about data modeling aspect, some administration consideration must be assessed too, but this is outside of the task so I will skip it. Most people use MongoDB to store log only, this can be understandable because log is very schema vollatile, so the flexible schema approach is best used here. Also for auditing purpose, compliance usually require the data underlying is immutable. MongoDB have capped collection that forbid all update on the collection, even root account cannot modify the data unless dropping and repoppulate data, so storing audit in MongoDB have this advantage too. Newest MongoDB have timeseries collection and clustered collection, so if we have some data that require these feature, we can consider using MongoDB.

For Neo4j, the best use for it is of course graph problem such as relationship or fraud detection. I lack some basic knowledge about graph real-world problem so need to have some reseach running for it too.

#### Observability

For monitoring aspect, we must approach in 2 aspect: technical and business.

For technical, all basic metrics related to PostgreSQL and its performance need to be captured. So we started with basic metrics for all DBMS: cpu, memory, IO, internal log (for PostgreSQL: WAL log), locking/waiting, connections, cache hit/miss, index ultilization. Then focus on PostgreSQL specific metrics: vacuum, dead tuples, transaction id.

For business, we need to monitor about query, procedure duration, especially related to core business. But this aspect we don't have much context so need some thought later.

#### Design write-up

Our analysis can cover most of ADR here, but task requires some more though about standards and microservices aspect so I need to cover them too.

#### Tools

- I am very familiar with MongoDB and Grafana.
- PostgreSQL and Neo4j not so much since I don't have the chance to actually maintain those services on production yet, but have some knowledge about them; so need to study more.
- About Flyway and Liquibase, I have no idea, so my appoach will be adhoc script first, then have AI do some search for me about these system to see if I can grasp the gist of these system or not. 

