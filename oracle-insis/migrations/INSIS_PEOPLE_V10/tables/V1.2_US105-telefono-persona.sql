--liquibase formatted sql

--changeset fernando:V1.2-1
ALTER TABLE P_PEOPLE ADD (PHONE VARCHAR2(30));
--rollback ALTER TABLE P_PEOPLE DROP COLUMN PHONE;
