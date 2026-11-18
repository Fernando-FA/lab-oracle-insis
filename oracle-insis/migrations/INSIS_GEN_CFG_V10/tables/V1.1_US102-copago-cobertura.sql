--liquibase formatted sql

--changeset fernando:V1.1-1
ALTER TABLE CFG_COVER ADD (COPAY_PCT NUMBER(5,2));
--rollback ALTER TABLE CFG_COVER DROP COLUMN COPAY_PCT;
