# Remote state backend for the production platform. The bucket is created by
# the aws-iac-foundations bootstrap stack, not by this repository.
#
#   terraform init -backend-config=backend.hcl

bucket       = "acme-tfstate-222222222222"
key          = "aws-eks-platform/prod/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
