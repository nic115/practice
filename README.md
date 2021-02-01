![bastion_infrastructure](https://user-images.githubusercontent.com/78341786/106430227-69881d00-6463-11eb-802c-5de1d0020da5.png)

I have created a VPC (10.0.0.0/16) that could host public web applications, as well as, private databases that would not be publically accessible.
The network comprises of two subnets one public and one private. 
Inside the public subnet (10.0.0.0/24) we host:

- two EC2 instances; one hosting a web-application (wordpress) and the other the bastion (for access to the private network).
- NAT gateway that connects the bastion host to the public subnet.

Inside the public subnet (10.0.1.0/24) we have:

- a database server. 

In the terraform file, we start by configuring the provider to use (in this case AWS). Access key and secret key have been removed for confidentiality.

Then we define some global variables that will come in handy, later on. The variable key_name- where we will store our private key- and base_path is the the path to our project.

Under VPC, we have the syntax to create our vpc and private subnet.

For ease of use, we create the private and public keys. This avoids having to keep sharing them to create a connection.

The gateway syntax follows, and it is associated to the vpc created earlier.

To route our traffic I have created two route tables. 

- igw_route_table -points to the intenet gateway and we associate it with the whole subnet.
- NAT_route_table -as earlier discussed, connects the bastion host to the private subnet.

Now we create an elastic IP for the instances innour vpc, in particular for our NAT gateway that we are creating.

In the Bastion section, we have our public subnet, instance (running Linux2 on a t2.micro)  in which we are providing some information to later ssh into the private subnet, also we are associating a security group to it. In the security group we specify which ports data can go through. In this case, ingress connections are only allowed through port 22 (ssh), for egress there is no limit, either tcp or udp.

Similar to the bastion section, in the app section, we create the instance that holds the word press app and we define the security rules to access it. Ports 80 and 22 for ingress and anywhere for egress.

Finally, we create the private subnet, where we have the security group and instance for the database server. This should be preconfigured and and configured on deployment, Ansible would complement nicely.
