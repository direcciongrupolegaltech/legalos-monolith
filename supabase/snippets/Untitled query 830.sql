INSERT INTO public.firms (id, name, nit) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Firma A', '12345678-9'),
  ('b0000000-0000-0000-0000-000000000002', 'Firma B', '12345678-0');

INSERT INTO public.user_profiles (id, first_name, last_name, email) VALUES
  ('a1111111-1111-1111-1111-111111111111', 'Abogado', 'Firma A', 'abogado.a@firm.com'),
  ('b2222222-2222-2222-2222-222222222222', 'Abogado', 'Firma B', 'abogado.b@firm.com');

INSERT INTO public.firm_members (firm_id, user_id, role_id) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'lawyer'),
  ('b0000000-0000-0000-0000-000000000002', 'b2222222-2222-2222-2222-222222222222', 'lawyer');

INSERT INTO public.cases (id, firm_id, case_number, title) VALUES
  ('c1111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'EXP-001', 'Caso Confidencial Firma A'),
  ('c2222222-2222-2222-2222-222222222222', 'b0000000-0000-0000-0000-000000000002', 'EXP-002', 'Caso Confidencial Firma B');


SET LOCAL request.jwt.claims = '{"sub": "a1111111-1111-1111-1111-111111111111", "role": "authenticated"}';

SELECT id, case_number, title FROM public.cases;

SELECT * FROM firms