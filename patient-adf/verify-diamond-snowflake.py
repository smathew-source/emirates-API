"""Verify live source-to-snowflake values and audit records; optionally test rollback."""
import json
import sys
from diamond_sql import connect

with connect('Diamond02') as db:
    c=db.cursor()
    c.execute('SELECT PatientId,GivenName,FamilyName,DateOfBirth,City,Email FROM dbo.Patient ORDER BY PatientId')
    patients=c.fetchall()
    c.execute('SELECT DoctorId,GivenName,FamilyName,Specialty,Email,IsActive FROM dbo.Doctor ORDER BY DoctorId')
    doctors=c.fetchall()
    c.execute('SELECT AppointmentId,PatientId,DoctorId,StartsAtUtc,EndsAtUtc,Status,Reason,CostGBP FROM dbo.Appointment ORDER BY AppointmentId')
    appointments=c.fetchall()
with connect() as db:
    c=db.cursor()
    c.execute('SELECT p.PatientId,p.GivenName,p.FamilyName,p.DateOfBirth,g.CityName,p.Email FROM dw.DimPatient p JOIN dw.DimCity g ON g.CityKey=p.CityKey ORDER BY p.PatientId')
    assert c.fetchall()==patients,'Patient dimension mismatch'
    c.execute('SELECT d.DoctorId,d.GivenName,d.FamilyName,s.SpecialtyName,d.Email,d.IsActive FROM dw.DimDoctor d JOIN dw.DimSpecialty s ON s.SpecialtyKey=d.SpecialtyKey ORDER BY d.DoctorId')
    assert c.fetchall()==doctors,'Doctor dimension mismatch'
    c.execute('SELECT AppointmentId,PatientId,DoctorId,StartsAtUtc,EndsAtUtc,Status,Reason,CostGBP FROM dw.vAppointmentDetails ORDER BY AppointmentId')
    assert c.fetchall()==appointments,'Appointment fact mismatch'
    c.execute("SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0 AND parent_object_id IN (OBJECT_ID('dw.DimPatient'),OBJECT_ID('dw.DimDoctor'),OBJECT_ID('dw.FactAppointment'))")
    assert c.fetchone()[0]==5,'Expected five trusted snowflake relationships'
    counts={}
    for name in ['DimCity','DimSpecialty','DimPatient','DimDoctor','DimDate','FactAppointment']:
        c.execute('SELECT COUNT(*) FROM dw.'+name)
        counts[name]=c.fetchone()[0]
    c.execute('SELECT RunId,PatientRows,DoctorRows,AppointmentRows,AppointmentAmountGBP FROM etl.LoadAudit ORDER BY LoadedAtUtc')
    audit=c.fetchall()
    print(json.dumps({'counts':counts,'audit':[list(r) for r in audit]},default=str))
    if '--test-rollback' in sys.argv:
        c.execute('SELECT AppointmentId,PatientKey,DoctorKey,CostGBP FROM dw.FactAppointment ORDER BY AppointmentId')
        before=c.fetchall()
        c.execute('BEGIN TRANSACTION; UPDATE stg.Appointment SET PatientId=-1 WHERE AppointmentId=(SELECT MIN(AppointmentId) FROM stg.Appointment);')
        try:
            c.execute('EXEC dw.LoadAppointments;')
        except Exception as error:
            c.execute('IF @@TRANCOUNT>0 ROLLBACK;')
            assert 'missing patient or doctor' in str(error),str(error)
        else:
            c.execute('IF @@TRANCOUNT>0 ROLLBACK;')
            raise AssertionError('Invalid foreign reference was accepted')
        c.execute('SELECT AppointmentId,PatientKey,DoctorKey,CostGBP FROM dw.FactAppointment ORDER BY AppointmentId')
        assert c.fetchall()==before,'Failed load modified facts'
        c.execute('SELECT COUNT(*) FROM stg.Appointment WHERE PatientId=-1')
        assert c.fetchone()[0]==0,'Test staging change was not rolled back'
        print('PASS: invalid references rejected; staging and facts rolled back')
    print('PASS: live source values match all snowflake dimensions and appointment facts')
