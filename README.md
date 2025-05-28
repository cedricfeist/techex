# Tasky App

This project includes terraform code to deploy a [tasky](https://github.com/jeffthorne/tasky) application on AWS. The architecture can be found below. 

Prerequisites:
- AWS Credentials (eg. via aws cli) .
- [tasky image](https://github.com/jeffthorne/tasky) hosted on an availabile registry and image configured in the kubernetes deployment. 
- (Optional) DataDog API Key to register the Agents. 

![AWS network diagram](https://github.com/user-attachments/assets/159d4d8a-37af-49c9-9c8b-7746fd14af44)

To apply the infrastructure, configure the variables and run the following commands in the same directory as the terraform files.

```
terraform init
terraform apply
```

Once applied, the application will be reachable from the output lb_dns_endpoint. 

To Destroy the infrastructure:
```
terraform destroy
```

> [!WARNING]
> This configuration contains intentional misconfiguration and vulnerabilities including outdated images and more. 