/**
 * src/modules/auth/services/auth-service.ts
 * Servicio Centralizado de Autenticación, Registro y Gestión de Invitaciones Multi-Tenant.
 */

import { createClient } from '@/lib/supabase/server';

export interface SignUpInput {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
}

export interface InvitationInput {
  firmId: string;
  email: string;
  roleId: 'administrator' | 'lawyer' | 'assistant';
}

export class AuthService {
  /**
   * Inicio de sesión con correo y contraseña en Supabase Auth.
   */
  static async signIn({ email, password }: { email: string; password: string }) {
    const supabase = await createClient();
    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    });
    return { success: !error, error: error?.message || null, user: data.user };
  }

  /**
   * Registro de nuevo usuario (dispara automáticamente el trigger handle_new_user).
   */
  static async signUp({ email, password, firstName, lastName }: SignUpInput) {
    const supabase = await createClient();
    const { data, error } = await supabase.auth.signUp({
      email: email.trim().toLowerCase(),
      password,
      options: {
        data: {
          first_name: firstName.trim(),
          last_name: lastName.trim(),
        },
      },
    });
    return { success: !error, error: error?.message || null, user: data.user };
  }

  /**
   * Generación de invitación segura a firma por token (Solo Administradores).
   */
  static async createInvitation({ firmId, email, roleId }: InvitationInput) {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) throw new Error('Usuario no autenticado.');

    // Verificar permiso de Administrador en la Firma
    const { data: adminMember } = await supabase
      .from('firm_members')
      .select('role_id')
      .eq('firm_id', firmId)
      .eq('user_id', user.id)
      .eq('role_id', 'administrator')
      .single();

    if (!adminMember) {
      return { success: false, error: 'Solo un administrador puede enviar invitaciones.' };
    }

    const token = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

    const { data: invitation, error } = await supabase
      .from('firm_invitations')
      .insert({
        firm_id: firmId,
        email: email.trim().toLowerCase(),
        role_id: roleId,
        token,
        invited_by: user.id,
        expires_at: expiresAt,
        status: 'pending',
      })
      .select()
      .single();

    if (error) return { success: false, error: error.message, token: null };
    return { success: true, error: null, token: invitation.token };
  }

  /**
   * Aceptación de invitación a firma mediante token válido.
   */
  static async acceptInvitation(token: string) {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) return { success: false, error: 'Debes autenticarte para aceptar la invitación.' };

    const { data: invitation, error: invError } = await supabase
      .from('firm_invitations')
      .select('*')
      .eq('token', token)
      .eq('status', 'pending')
      .gt('expires_at', new Date().toISOString())
      .single();

    if (invError || !invitation) {
      return { success: false, error: 'La invitación es inválida o ha expirado.' };
    }

    const { error: memberError } = await supabase.from('firm_members').insert({
      firm_id: invitation.firm_id,
      user_id: user.id,
      role_id: invitation.role_id,
      is_active: true,
    });

    if (memberError) return { success: false, error: memberError.message };

    await supabase
      .from('firm_invitations')
      .update({ status: 'accepted' })
      .eq('id', invitation.id);

    return { success: true, error: null, firmId: invitation.firm_id };
  }
}
