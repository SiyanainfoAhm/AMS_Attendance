## Migrations

- All database objects must be prefixed with `AMS_`:
  - tables, functions, procedures, views, triggers, constraints, indexes
- Multi-tenancy:
  - all business tables include `AMS_company_id`
  - access is enforced in functions/procedures used by APIs

