async function deleteAllUsers(db) {
  return db.query("DELETE FROM users");
}

module.exports = { deleteAllUsers };
