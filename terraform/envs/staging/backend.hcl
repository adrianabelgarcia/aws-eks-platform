# Remote state backend for the staging platform. The bucket is created by the
# aws-iac-foundations bootstrap stack, not by this repository.
#
#   terraform init -backend-config=backend.hcl

bucket       = "acme-tfstate-111111111111"
key          = "aws-eks-platform/staging/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
