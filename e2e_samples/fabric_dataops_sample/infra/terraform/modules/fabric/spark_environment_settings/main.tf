terraform {
  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "0.1.0-beta.3"
    }
  }
}

resource "fabric_spark_environment_settings" "example" {
  workspace_id       = var.workspace_id
  environment_id     = var.environment_id
  publication_status = var.publication_status

  driver_cores  = 4
  driver_memory = "28g"

  executor_cores  = 4
  executor_memory = "28g"

  runtime_version = var.runtime_version

  dynamic_executor_allocation = {
    enabled       = true
    min_executors = 1
    max_executors = 2
  }

  pool = {
    name = var.spark_pool_name
    type = var.spark_pool_type
  }

  spark_properties = {
    "spark.native.enabled" : "true",
    "spark.shuffle.manager" : "org.apache.spark.shuffle.sort.ColumnarShuffleManager"
  }
}