terraform {
  backend "s3" {
    bucket = "sctp-tfstate-ce13"
    key    = "tk/tf-coaching9.tfstate"
    #use_lockfile = true
    region = "us-east-1"
  }
}