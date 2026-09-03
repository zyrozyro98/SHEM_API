const fetch = require('node-fetch');
const db = require('../db');

// Expects: Authorization: Bearer <access_token>
// Requires env: SUPABASE_URL, SUPABASE_ANON_KEY

async function getSupabaseUser(token) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) return null;
  const url = `${process.env.SUPABASE_URL.replace(/\/+$/,'')}/auth/v1/user`;
  const resp = await fetch(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: process.env.SUPABASE_ANON_KEY
    }
  });
  if (!resp.ok) return null;
  const data = await resp.json();
  return data.user || data;
}

async function authMiddleware(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing Authorization header' });
  }
  const token = auth.slice('Bearer '.length);
  try {
    const supaUser = await getSupabaseUser(token);
    if (!supaUser || !supaUser.id) return res.status(401).json({ error: 'Invalid token' });
    // Load profile from DB
    const { rows } = await db.query('select id, auth_user_id, role from profiles where auth_user_id = $1', [supaUser.id]);
    if (!rows || rows.length === 0) {
      // If no profile, allow minimal user object with auth id only
      req.user = { auth_user_id: supaUser.id };
      return next();
    }
    req.user = rows[0];
    // attach supabase user metadata as well
    req.user.supabase = supaUser;
    next();
  } catch (err) {
    console.error('auth error', err);
    res.status(500).json({ error: 'Auth verification failed' });
  }
}

module.exports = { authMiddleware, getSupabaseUser };
