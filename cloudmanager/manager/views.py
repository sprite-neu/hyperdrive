from django.shortcuts import render
from django.http import HttpResponse
from django.template import loader
from subprocess import call
import os

"""This renders the index.html page from the templates directory. It fills up the radio buttons from the values in the
	hypervisors and cloudStacks arrays"""
def index(request):
	hypervisors = ["VMWare-vSphere", "Xen-Server", "Microsoft-Hyper-V", "KVM"]
	cloudStacks = ["Apache-CloudStack", "Cloud-Foundry", "RedHat-OpenShift", "None"]
	reboot = ["Yes", "No"]
	template = loader.get_template('manager/index.html')
	context = {
		'hypervisors': hypervisors,
		'cloudStacks': cloudStacks,
		'reboot': reboot
	}

	return HttpResponse(template.render(context, request))


"""This function renders the status.html page from the templates directory. It also takes the request object from the 
	index method and determines the selected cloud configuration and saves it to a file 'cloud_configuration.txt' located
	at /home/cloudmanager. This file is fetched by the shell script running on client machines to determine the cloud
	configuration to deploy"""
def status(request):
	template = loader.get_template('manager/status.html')
	context = {
		'test': 'cool' # We need some kind of context to render the page. This doesn't actually do anything
	}


	if (request.POST):
		save_path = '/home/cloudmanager/'
		if os.path.isfile(save_path+"cloud_configuration.txt") == True: # If the file already exists, remove it
			os.remove(save_path+"cloud_configuration.txt")

		cloudConfigPath = os.path.join(save_path, "cloud_configuration.txt")

		#print request.POST.get('hypervisorRadios')
		print(cloudConfigPath)

		file_object = open(cloudConfigPath, 'w') # Open the file for writing

		hyperV = request.POST.get('hypervisorRadios') # Get the selected hypervisor
		rebootStatus = request.POST.get('rebootRadios') # Get reboot option

		print(rebootStatus)

		if rebootStatus == "Yes":
			print "YES"
			file_object.write("reboot_status=YES\n")

		else:
			print "NO"
			file_object.write("reboot_status=NO\n")
		
		# At the moment we only support KVM, KVM + Apache Cloudstack and XEN, so we only check for those configuraions
		if hyperV == "KVM":
			if request.POST.get('cloudstackRadios') == "Apache-CloudStack":
				print 'KMV-CLOUDSTACK'
				file_object.write("hyp_name=KVM-CLOUDSTACK") # Write to file
				
 			elif request.POST.get('cloudstackRadios') == "None":
 				print "KVM"
 				file_object.write("hyp_name=KVM")

 		elif hyperV == "Xen-Server": 	
			print 'XENSERVER'
 			file_object.write("hyp_name=XENSERVER")
 	
        else:
    		print "Oops! Something is broken."

		file_object.close() # Close the file

	return HttpResponse(template.render(context, request))