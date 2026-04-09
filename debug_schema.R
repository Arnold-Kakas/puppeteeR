setwd("C:/Users/Arnold/Documents/GitHub/puppeteeR")
devtools::load_all(".", quiet = TRUE)

ws <- workflow_state(result = list(default = NULL))
sch <- ws[["schema"]]
cat("schema class:", class(sch), "\n")
cat("schema length:", length(sch), "\n")
cat("schema names:", names(sch), "\n")

# Test creating fresh state from schema
ws2 <- WorkflowState$new(sch)
cat("ws2 keys:", ws2$keys(), "\n")
cat("ws2 result:", ws2$get("result"), "\n")
