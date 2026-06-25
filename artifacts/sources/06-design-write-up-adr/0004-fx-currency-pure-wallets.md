# 0004. Cross-currency transfers use currency-pure wallets and house FX wallets

- Status: Accepted
- Date: 2026-06-25
- Deciders: Bùi Đức Trí

## Context

A transfer where a VND wallet funds a USD wallet has a value that depends on the VND/USD rate. There are two ways to keep the ledger sound across currencies: (1) pick a base currency and convert every entry into it; (2) keep every wallet single-currency and route a cross-currency move through the platform's own FX wallets as two same-currency legs.

Option (1) suits an internal customer-asset system with one reporting currency, but a payments platform must keep each currency true to itself.

## Decision

Every `wallet` is single-currency. A cross-currency transfer is **one transaction** with two balanced legs routed through platform `FX_POSITION` wallets (for example `FX_VND`, `FX_USD`), under one idempotency key. The platform's own roles live on `account.type` as a small chart of accounts: `CUSTOMER`, `PLATFORM_FLOAT`, `PLATFORM_REVENUE`, `MERCHANT_PAYABLE`, `FX_POSITION`. These platform accounts are what let a fee, a top-up, or an FX leg balance.

Worked example (A1 sends value so A2 receives 1 USD at 27,000 VND/USD):

| wallet | type | amount | currency |
|---|---|---|---|
| A1_VND | DEBIT | 27000.0000 | VND |
| FX_VND | CREDIT | 27000.0000 | VND |
| FX_USD | DEBIT | 1.0000 | USD |
| A2_USD | CREDIT | 1.0000 | USD |

## Consequences

- Each currency balances on its own (ADR 0002); the rate never enters the balance check.
- A "simple" cross-currency transfer is four entries, not one; application and reporting code must expect multi-leg transactions.
- The platform carries FX position in its `FX_POSITION` wallets, which is also where FX profit and loss becomes visible.
- In-flight money uses per-account **holding wallets**, not a central suspense account (see CONTEXT.md).

## Alternatives considered

- **Base-currency conversion (option 1)**: one wallet per account, all values normalised to a base currency. Good for an internal asset system with a single reporting currency; wrong for a payments platform that must hold real balances in each currency.
- **Role on `wallet`, plus a `SUSPENSE` account**: rejected. Holding is a wallet-level kind, and the account role belongs on `account.type`; a central suspense account is the wrong abstraction for per-account in-flight money.

## Provenance

The currency-pure-wallets-plus-house-FX-wallets choice (option 2 over a base currency) is mine, from the section 2.1 reasoning. AI research supplied the chart-of-accounts vocabulary; I rejected the AI's suggestion to put the role on `wallet` and to add a `SUSPENSE` account.
