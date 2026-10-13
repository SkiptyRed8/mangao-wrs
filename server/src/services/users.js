// How a user is sent to the app.
function shapeUser(u) {
  return {
    id: u.user_id,
    name: u.full_name,
    phone: u.phone_number,
    email: u.email,
    role: u.role,
    active: !!u.is_active,
  };
}

module.exports = { shapeUser };
