-- Se ejecuta como SYSDBA en la raíz (CDB). Crea DESA, TEST y PROD desde la semilla.
WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON
DECLARE
  n NUMBER;
BEGIN
  FOR p IN (SELECT column_value AS pdb FROM TABLE(sys.odcivarchar2list('DESA', 'TEST', 'PROD'))) LOOP
    SELECT COUNT(*) INTO n FROM cdb_pdbs WHERE pdb_name = p.pdb;
    IF n = 0 THEN
      EXECUTE IMMEDIATE 'CREATE PLUGGABLE DATABASE ' || p.pdb ||
        ' ADMIN USER pdbadmin IDENTIFIED BY "Pdb_' || p.pdb || '_1"' ||
        ' FILE_NAME_CONVERT = (''/opt/oracle/oradata/FREE/pdbseed/'', ''/opt/oracle/oradata/FREE/' || p.pdb || '/'')';
      EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ' || p.pdb || ' OPEN';
      EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ' || p.pdb || ' SAVE STATE';
      DBMS_OUTPUT.PUT_LINE(p.pdb || ': creada');
    ELSE
      DBMS_OUTPUT.PUT_LINE(p.pdb || ': ya existe');
    END IF;
  END LOOP;
END;
/
EXIT
