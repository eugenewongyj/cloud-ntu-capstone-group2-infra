terraform {
  backend "s3" {
    #bucket = "sctp-tfstate-ce13"
    bucket = "sctp-core-tfstate"
    key    = "group2/group2-github-oidc-bootstrap.tfstate"
    #region = "us-east-1"
    region = "ap-southeast-1"
  }
}