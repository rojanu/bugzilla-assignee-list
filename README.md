The Assignee List is a Bugzilla extension that implements a list of possible assignees for components
## Installation
* Download the latest release.
* Unpack the download. This will create a directory called "AssigneeList".
* Move the "AssigneeList" directory into the "extensions" directory in your Bugzilla installation.
Go to your Bugzilla directory
Apply the patch and run checksetup.pl
```
patch -p0 -i extensions/AssigneeList/patch-4.1.diff
./checksetup.pl
```
