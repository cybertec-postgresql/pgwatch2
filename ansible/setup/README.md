How to deploy pgwatch2 using ansible.

Copy inventory\_example.yaml to another file and modify it to include hosts you need to deploy pgwatch2.

Also modify the variable `databases`, which should include all the monitored databases.

After your inventory file is ready, run the command:

```
ansible-playbook playbook.yaml -i <inventory_file>
```  
