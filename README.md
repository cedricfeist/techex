# Tasky App

This project includes terraform code to deploy a [tasky](https://github.com/jeffthorne/tasky) application on AWS. The architecture can be found below. 

Prerequisites:
- AWS Credentials
- [tasky image](https://github.com/jeffthorne/tasky) hosted on an availabile registry
- (Optional) DataDog API Key to register the Agent. 

![AWS network diagram](https://github.com/user-attachments/assets/159d4d8a-37af-49c9-9c8b-7746fd14af44)

To apply the infrastructure, configure the variables and run the following commands in the same directory as the terraform files.

```
terraform init
terraform apply
```

Once applied, the application will be reachable from the output 

To Destroy the infrastructure:
```
terraform destroy
```
