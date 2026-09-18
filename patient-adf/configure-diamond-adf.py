"""Grant ADF access only to source reads, staging inserts and load/reset procedures."""
from diamond_sql import connect,FACTORY

for database in ['Diamond02','DiamondWarehouse']:
    with connect(database) as db:
        cur=db.cursor()
        cur.execute(f"IF DATABASE_PRINCIPAL_ID(N'{FACTORY}') IS NULL CREATE USER [{FACTORY}] FROM EXTERNAL PROVIDER;")
        if database=='Diamond02':
            for table in ['Patient','Doctor','Appointment']:
                cur.execute(f'GRANT SELECT ON OBJECT::dbo.{table} TO [{FACTORY}];')
        else:
            for table in ['Patient','Doctor','Appointment']:
                cur.execute(f'GRANT SELECT, INSERT ON OBJECT::stg.{table} TO [{FACTORY}]; GRANT EXECUTE ON OBJECT::etl.Reset{table} TO [{FACTORY}];')
            cur.execute(f'GRANT EXECUTE ON OBJECT::dw.LoadAppointments TO [{FACTORY}];')
            for table in ['FactAppointment','DimPatient','DimDoctor','DimDate']:
                cur.execute(f'GRANT SELECT ON OBJECT::dw.{table} TO [{FACTORY}];')
        print('Configured managed identity permissions:',database)
