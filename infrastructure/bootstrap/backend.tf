# The bucket is created by the first local-state apply. Backend details are supplied
# at init time; the bootstrap and session roots use separate state keys.
terraform {
  backend "s3" {}
}
