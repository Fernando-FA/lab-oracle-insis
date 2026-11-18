--liquibase formatted sql logicalFilePath:fadata/insis-12.7.0/INSIS_PEOPLE_V10.sql
-- Simula lo que ya trae la BD de INSIS: tablas del producto y su historial en DATABASECHANGELOG.

--changeset fadata:P_PEOPLE-12.7.0
CREATE TABLE P_PEOPLE (
  MAN_ID     NUMBER        PRIMARY KEY,
  NAME       VARCHAR2(200) NOT NULL,
  EGN        VARCHAR2(20),
  MAN_COMP   NUMBER(1)     DEFAULT 1 NOT NULL
);
--rollback DROP TABLE P_PEOPLE;

--changeset fadata:P_PEOPLE-datos-12.7.0
INSERT INTO P_PEOPLE (MAN_ID, NAME, EGN, MAN_COMP) VALUES (1001, 'PACIFICO SALUD EPS', '20431115825', 2);
INSERT INTO P_PEOPLE (MAN_ID, NAME, EGN, MAN_COMP) VALUES (1002, 'JUAN PEREZ', '40123456', 1);
--rollback DELETE FROM P_PEOPLE WHERE MAN_ID IN (1001, 1002);
