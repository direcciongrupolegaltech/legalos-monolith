DO $$
BEGIN
    INSERT INTO public.cases (firm_id, case_number, title)
    VALUES ('b0000000-0000-0000-0000-000000000002', 'EXP-HACK', 'Intento de Inyección');

    	RAISE EXCEPTION 'FALLO: RLS permitió la inserción cruzada de tenant.';
EXCEPTION
    	WHEN check_violation THEN
        RAISE NOTICE 'SUCCESS [RLS Inyección]: Inserción cruzada bloqueada por RLS (WITH CHECK violation).';
END $$;

ROLLBACK;
