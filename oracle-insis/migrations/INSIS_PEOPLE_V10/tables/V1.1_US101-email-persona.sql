--liquibase formatted sql

--changeset fernando:V1.1-1
ALTER TABLE P_PEOPLE ADD (EMAIL VARCHAR2(200));
--rollback ALTER TABLE P_PEOPLE DROP COLUMN EMAIL;
