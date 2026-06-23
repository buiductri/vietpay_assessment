# 00-journal revision notes

Original: `00-journal.md`
Revised: `00-journal-revised.md`

Scope: proofreading only. The section order, technical intent, first-person journal style, and writing flow were kept.

## Global fixes

- Corrected typos such as `ultilize` -> `utilize`, `bigest` -> `biggest`, `mounth` -> `month`, `specificed` -> `specified`, `reporing` -> `reporting`, `pre-aggreate` -> `pre-aggregate`, `futher` -> `further`, `constaint` -> `constraint`, `assumtion` -> `assumption`, `Polygot` -> `Polyglot`, `ultilization` -> `utilization`, `vollatile` -> `volatile`, `repoppulate` -> `repopulating`, `reseach` -> `research`, `appoach` -> `approach`, and `adhoc` -> `ad hoc`.
- Corrected subject-verb agreement, for example `assessment ask` -> `assessment asks`, `the table have` -> `the table has`, `query scan` -> `query scans`, and `PostgreSQL need` -> `PostgreSQL needs`.
- Corrected plural and singular forms, for example `index` -> `indexes` where plural was intended, `tuple` -> `tuples`, `currency` -> `currencies`, `artifact` -> `artifacts`, `DBMS` -> `DBMSs`, and `transaction id` -> `transaction IDs`.
- Added missing articles and prepositions, for example `the main database`, `the application`, `into the new column`, `with the help of AI`, and `in production`.
- Smoothed run-on sentences and comma usage while keeping the same paragraphs and reasoning path.
- Standardized technical phrasing where needed: `entrypoint` -> `entry point`, `index only scan` -> `index-only scan`, `customer facing` -> `customer-facing`, `audit centric` -> `audit-centric`, and `PostgreSQL specific` -> `PostgreSQL-specific`.

## Detailed fixes by section

### Opening

- `This file is served as details step journal i have taken` -> `This file serves as a detailed step-by-step journal of what I have done`.
- Capitalized `I` and fixed the opening sentence structure.

### 1.1 Business Domain and Tech Stack

- `The assessment ask for designing` -> `The assessment asks us to design`.
- `fintech payment` -> `fintech payments`.
- `language term` -> `terminology`.
- `the main tech stack are PostgreSQL` -> `the main tech stack is PostgreSQL`.
- `not main experience tech stack` -> `it is not my main experience stack`.
- `To cover our weakness here` -> `To cover our weaknesses here`.
- Clarified `missing pieces` and `customer asset systems` without changing the point.

### 1.2 First impression, The transaction table

- `The transaction table is 50 mil rows and having additional 2 mil rows per month` -> `The transaction table has 50 million rows and receives an additional 2 million rows per month`.
- `The context mention` -> `The context mentions`.
- `Let's made some blind guess` -> `Let's make some blind guesses`.
- `if the table have index` -> `whether the table has indexes`.
- `performance killer` -> `performance killers` where plural was intended.
- `query scan` -> `query scans` and `query always need` -> `query always needs`.
- `If this is SQL Server` -> `If this were SQL Server`.
- `calculate the statement of all wallets` -> `calculate the statement for all wallets`.
- `save into a set of reporting tables` -> `save it into a set of reporting tables`.
- `2 physical one` -> `2 physical ones`.
- `prone to update` -> `prone to updates`.
- `specificed` -> `specified`, `Depend on the load` -> `Depending on the load`, `the time varied` -> `the time varies`, and `This also help` -> `This also helps`.
- `(live table vs archived table have different index strategy)` -> `(the live table and archived table have different index strategies)`.

### PostgreSQL and indexing discussion

- `the insights above can be apply` -> `the insights above can be applied`.
- `One of the bigest difference` -> `One of the biggest differences`.
- `does not modify tuple in place` -> `does not modify tuples in place`.
- `creates new tuple and update pointer` -> `creates a new tuple and updates the pointer`.
- `there are no cluster index in PostgreSQL neither` -> `there are no clustered indexes in PostgreSQL either`.
- `PostgreSQL index scan also have` -> `PostgreSQL index scans also have`.
- `multiple records of a tuple exists` -> `multiple records of a tuple can exist`.
- `by ensure the page is clean` -> `by ensuring the page is clean`.
- `speedup` -> `speed up`.
- `index strategy prefer` -> `index strategy follows`.
- `status mostly in settled status` -> `the status is mostly settled`.
- `indexing status have limited benefit` -> `indexing status has limited benefit`.
- `we have currency, this is a design problem` -> `we have currency, which is a design problem`.
- `use aggregate on SELECT` -> `use an aggregate in SELECT`.
- `multiple currency` -> `multiple currencies`.
- `it make query harder` -> `it makes the query harder`.
- `lean into keep currency` -> `lean toward keeping currency`.

### Index option bullets

- `we must use index` -> `we must use an index`.
- `the include is optional` -> `the INCLUDE is optional`.
- `index only scan working` -> `index-only scan works`.
- `query for customer always have wallet_id` -> `queries for customers always have wallet_id`.
- `emit a plan what can ultilize` -> `emit a plan that can utilize`.
- `SELECT unique wallet_id then JOIN` -> `selecting unique wallet_id, then joining`.
- `other problem that this query is nested loop` -> `another problem where this query is a nested loop`.
- `This pattern is focusing` -> `This pattern focuses`.
- `reporing query` -> `reporting query`.
- `wallet_id then will be useless` -> `wallet_id will then be useless`.
- `if neccessary` was corrected to `unless necessary` to preserve the intended meaning of avoiding that index unless needed.
- `Also need thorough testing to ensure` -> `This also needs thorough testing`.
- `pre-aggreate` -> `pre-aggregate`.
- `range query by month will only touch needed partition` -> `a range query by month will only touch the needed partition`.
- `This also enable futher management best practice` -> `This also enables further management best practices`.

### Core model

- `entrypoint` -> `entry point`.
- `expand the entrypoint at transactions table` -> `expand from the transactions table as the entry point`.
- `payment domain` gained the missing article: `the payment domain`.
- `This is new domain` -> `This is a new domain`.
- `study for the correct business understanding` -> `study to get the correct business understanding`.
- `before continue` -> `before continuing`.
- `most of the term` -> `most of the terms`.
- `run a research` -> `run research`.
- `have deep understanding` -> `have a deep understanding`.
- `for designing the best schema` -> `to design the best schema`.
- `Delivery artifact` -> `Delivery artifacts`.
- `reuse them` -> `reuse it`, because the sentence refers to the visualization method.
- `a generator service that mimic` -> `a generator service that mimics`.
- `The extra reasoning requirement we done a bit` -> `We already did a bit of the extra reasoning requirement`.
- `when analyze` -> `when analyzing`.

### Query & performance

- `Because of we don't have` -> `Because we don't have`.
- `analysis in this section need` -> `analysis in this section needs`.
- `This require data` -> `This requires data`.
- `not sure we can done it in time` -> `not sure we can get it done in time`.
- Split the final long sentence so the pacing remains readable.

### Zero-downtime migration

- `a new column settlement_batch_id, NOT NULL and need to be update live` -> `a new NOT NULL column, settlement_batch_id, and it needs to be updated live`.
- `The goal is have` -> `The goal is to have`.
- `this task only care` -> `this task only cares`.
- `deployment step only` -> `deployment steps only`.
- `With above assumtion` -> `With the above assumption`.
- `the task becomes having a base script` -> `the task becomes creating a base script`.
- `requirements for value` -> `requirements for the value`.
- `zero downtime need to have extra care about internal working` -> `zero downtime needs extra care around the internal workings`.
- `long running query` -> `long-running queries`.
- `transaction commit & rollback` -> `transaction commits and rollbacks`.
- `via each steps` -> `via each step`.
- `do not break the old version application` -> `does not break the old version of the application`.
- `3 stage deployment` -> `3-stage deployment`.
- `without constaint` -> `without a constraint`.
- `application deployment that will populate data` -> `deploy the application that will populate data`.
- `the best way is not have application show new changes yet` -> `without showing new changes yet`.
- `prefer second` -> `I prefer the second`.
- `backfilling data` -> `backfill data`.
- `before turn on flag feature` -> `before turning on the feature flag`.
- `This need extra collaboration` -> `This needs extra collaboration`.

### Polyglot modelling

- `Polygot` -> `Polyglot`.
- `other DBMS` -> `other DBMSs`.
- `Neo4j need` -> `Neo4j needs`.
- `which I a bit lack` -> `which I lack a bit`.
- Removed one repeated sentence-starting `But` while keeping the same flow.
- `its best strong point` -> `its strongest points`.
- `document centric` -> `document-centric`.
- `self developed` -> `self-developed`.
- `MongoDB take the ultilization to the best` -> `MongoDB makes good use of document storage and the aggregation framework`.
- `builtin HA solution` -> `built-in HA solution`.
- `which most RDBMS miss` -> `which most RDBMSs lack`.
- `not only about data modeling aspect` -> `not only about the data modeling aspect`.
- `administration consideration` -> `administrative considerations`.
- `storing log only` -> `store logs only`.
- `schema vollatile` -> `schema-volatile`.
- `compliance usually require` -> `compliance usually requires`.
- `the data underlying is immutable` -> `the underlying data to be immutable`.
- `capped collection` -> `capped collections`.
- `forbid all update` -> `forbid all updates`.
- `unless dropping and repoppulate data` -> `without dropping and repopulating data`.
- `Newest MongoDB` -> `The latest MongoDB`.
- `timeseries collection` -> `time series collections`.
- `data that require these feature` -> `data that requires these features`.
- `reseach running` -> `run some research`.

### Observability

- `in 2 aspect` -> `from 2 aspects`.
- `For technical` -> `For the technical side`.
- `we started` -> `we start`.
- `cpu, memory, IO` -> `CPU, memory, I/O`.
- `internal log` -> `internal logs`.
- `cache hit/miss` -> `cache hits/misses`.
- `index ultilization` -> `index utilization`.
- `PostgreSQL specific` -> `PostgreSQL-specific`.
- `transaction id` -> `transaction IDs`.
- `For business` -> `For the business side`.
- `we need to monitor about query` -> `we need to monitor query`.

### Design write-up

- `some more though` -> `some more thought`.
- `microservices aspect` -> `the microservices aspect`.

### Tools

- `PostgreSQL and Neo4j not so much` -> `I am not as familiar with PostgreSQL and Neo4j`.
- `don't have the chance` -> `have not had the chance`.
- `maintain those services on production` -> `maintain those services in production`.
- `so need to study more` -> `so I need to study more`.
- `appoach` -> `approach`.
- `adhoc script` -> `ad hoc scripts`.
- `these system` -> `these systems`.
