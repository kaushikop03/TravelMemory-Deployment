for deployement Of trevalmenory Web site the necessary steps and required resource creations
-------------------------------------------------------------------------------------------------------
step 1:
	set up your EC2 instance or you local WSL ubuntu system and configured it with 
	1  aws --version
	2  aws configure
	3  aws sts get-caller-identity
	4  aws configure get region
Step 2
	create project TravelMemory-Deployment on your WSL ubuntu system
	ansible
		|
	ScreenShots
		|
	terraform
		|
	like following folder structure

 
Step 3 : creating or prepare the files under terraform to prepare your EC2 Instances
	1	main.tf
	2 	outputs.tf
	3 	terraform.tfvars
	4	variable.tf
	5	versions.tf
	already shared code with githib repo
-----------------------------------------
Step 4 — Write the Terraform configuration
	write down code for your requirement synopsis to complete
----------------------------------------------------------------------
Step 5 — Validate and create the infrastructure
	Run these commands from the Terraform folder:
	cd terraform

	terraform init
	terraform fmt -recursive
	terraform validate
	terraform plan -out=tfplan
	terraform apply tfplan


	Review the plan before applying it. The NAT Gateway and its Elastic IP can incur charges even when the application has little traffic.

	After successful creation, configure terraform/outputs.tf to return at least:
	output "web_public_ip" {
	  value = aws_instance.web.public_ip
	}

	output "database_private_ip" {
	  value = aws_instance.database.private_ip
	}
---------------------------------------------------------------------------------
Record both IPs for Ansible. The database IP should be a private IP such as 10.0.2.x.
6. Part 2 — Configure the servers using Ansible
Step 6 — Connect to the EC2 instances
		After Terraform apply plan we have to check our EC2 web server connected through our WSL or ubuntu node
		and db server only connect from web EC2 instance
---------------------------------------------------------------------------------------
Step 7 — Prepare ansible file for Webserver and db server preparations
	ansible folder structure
	group_vars\web\vault.yml
	templates\backend.env.j2
	templates\nginx.conf.j2
	templates\travelmemory-backend.service.j2
	ansible.Conditions
	inventory.ini
	site.yml


Step 8 — Prepare and installation of mongo db 
	1) prepare you ansible file to setup db server with mongodb database
	2) after installation set password for travelmemory_app user
---------------------------------------------------------------------------
Step 9 — Deploy the backend
	The application README specifies the backend's MONGO_URI and port 3001. 

	UnpredictablePrashant/TravelMemory · GitHub




	Add the following tasks to the web play in site.yml:
		- name: Clone TravelMemory repository
		  ansible.builtin.git:
			repo: https://github.com/UnpredictablePrashant/TravelMemory.git
			dest: /opt/TravelMemory
			version: main

		- name: Install backend dependencies
		  community.general.npm:
			path: /opt/TravelMemory/backend
			state: present


	The community.general collection must be installed on your Ansible controller if you use this module:
	ansible-galaxy collection install community.general


	Create the backend .env file using an Ansible template, with secrets loaded from Ansible Vault. It should contain the equivalent of:
	PORT=3001
	MONGO_URI=mongodb://APP_DB_USER:URL_ENCODED_PASSWORD@10.0.2.x:27017/travelmemory?authSource=travelmemory
----------------------------------------------------------------------------------------------------------------
Step 10 — Build the frontend
	The repository README specifies REACT_APP_BACKEND_URL as the frontend's backend URL. 

	UnpredictablePrashant/TravelMemory · GitHub




	For a simple hosting arrangement, serve the React build through Nginx on port 80 and proxy API requests to the Node.js backend on port 3001. This keeps the Node.js port private from internet visitors.

	First, inspect the frontend source and identify how it constructs API URLs. Configure the backend URL to use the same public origin as the website, with a path such as /api only if the application supports that path or you update its API configuration accordingly.

	Add these deployment tasks to the web play in Ansible:
		- name: Install frontend dependencies
		  community.general.npm:
			path: /opt/TravelMemory/frontend
			state: present

		- name: Build React frontend
		  ansible.builtin.command:
			cmd: npm run build
			chdir: /opt/TravelMemory/frontend
		  environment:
			REACT_APP_BACKEND_URL: "http://YOUR_WEB_PUBLIC_IP:3001"


	The URL above is a temporary example for testing. For the final setup, use a same-origin Nginx proxy or a proper HTTPS API URL. React environment variables are generally embedded during the build, so changing a server environment variable after the build won't update the compiled JavaScript.

	Check that the build completes successfully and creates the frontend build/ directory.
------------------------------------------------------------------------------------
Step 11 — Configure Nginx
	Create an Nginx configuration file using an Ansible template. For example, the following configuration serves the built React application and proxies requests sent to /trip to the backend:
	server {
		listen 80;
		server_name _;

		root /var/www/travelmemory;
		index index.html;

		location / {
			try_files $uri $uri/ /index.html;
		}

		location /trip {
			proxy_pass http://127.0.0.1:3001/trip;
			proxy_set_header Host $host;
			proxy_set_header X-Real-IP $remote_addr;
			proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
			proxy_set_header X-Forwarded-Proto $scheme;
		}
	}


	This is a starting configuration, not a guaranteed complete route map. Inspect the application's API calls and add any other API routes it needs. The frontend must call URLs matching the proxy routes.

	Copy the build files to the Nginx document root:
	sudo mkdir -p /var/www/travelmemory
	sudo cp -r /opt/TravelMemory/frontend/build/. /var/www/travelmemory/


	Then validate and reload Nginx:
	sudo nginx -t
	sudo systemctl reload nginx
-----------------------------------------------------------
Step 12 — Keep the backend running after reboot
	Create a systemd service named travelmemory.service with these essential settings:
	[Unit]
	Description=TravelMemory Node.js Backend
	After=network.target

	[Service]
	Type=simple
	User=www-data
	WorkingDirectory=/opt/TravelMemory/backend
	EnvironmentFile=/etc/travelmemory/backend.env
	ExecStart=/usr/bin/node /opt/TravelMemory/backend/index.js
	Restart=always
	RestartSec=5

	[Install]
	WantedBy=multi-user.target


	Ensure the application files and environment file are readable by the service account. Store the environment file with restrictive permissions and do not expose it through Nginx.

	Enable the service:
	sudo systemctl daemon-reload
	sudo systemctl enable --now travelmemory
	sudo systemctl status travelmemory
------------------------------------------------------
Step 13 
	Checking of Url after hosting 
	curl -i http://localhost:3001/trip


	 
