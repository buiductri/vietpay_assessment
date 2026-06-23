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

