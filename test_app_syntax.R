# Test if app.R can be sourced without syntax errors
tryCatch({
  source('app.R')
  cat("SUCCESS: app.R sourced successfully!\n")
}, error = function(e) {
  cat("ERROR: Failed to source app.R\n")
  cat("Message:", conditionMessage(e), "\n")
  traceback()
})
