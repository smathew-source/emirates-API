"""Migrate existing warehouse, preserving keys and attributes, in one transaction."""
from pathlib import Path
from diamond_sql import connect,batches

with connect() as db:
    cur=db.cursor()
    cur.execute('SELECT AppointmentId,AppointmentKey,PatientKey,DoctorKey,DateKey,CostGBP FROM dw.FactAppointment ORDER BY AppointmentId')
    before=cur.fetchall()
    cur.execute('BEGIN TRANSACTION;')
    try:
        batches(cur,Path(__file__).with_name('sql')/'07-diamond-snowflake.sql')
        cur.execute('EXEC dw.LoadAppointments;')
        cur.execute('SELECT AppointmentId,AppointmentKey,PatientKey,DoctorKey,DateKey,CostGBP FROM dw.FactAppointment ORDER BY AppointmentId')
        assert cur.fetchall()==before,'Migration changed existing fact keys or amounts'
        cur.execute('SELECT COUNT(*) FROM dw.vAppointmentDetails')
        assert cur.fetchone()[0]==len(before)
        cur.execute('COMMIT;')
    except Exception:
        cur.execute('IF @@TRANCOUNT>0 ROLLBACK;')
        raise
    print('PASS: snowflake migration preserved fact keys, amounts and relationships')
