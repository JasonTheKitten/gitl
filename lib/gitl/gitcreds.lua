local driver = localRequire("driver")

local function userInputCredentialsHelper()
  print("This repository requires authentication to access.")
  io.write("Username: ")
  local username = io.read()

  print("WARNING: Do not enter passwords or tokens on multiplayer servers! It is a security risk!")
  io.write("Password/Token: ")
  local password = driver.readPassword()
  print("\n")

  return username, password
end

return {
  userInputCredentialsHelper = userInputCredentialsHelper
}