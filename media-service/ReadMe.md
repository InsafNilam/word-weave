python3 -m venv venv

source venv/bin/activate
.\venv\Scripts\Activate.ps1

Get-ExecutionPolicy -List
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\venv\Scripts\Activate.ps1

pip install -r requirements.txt

touch main.py
deactivate

git rm -r --cached venv/lib
fatal: pathspec 'venv/lib' did not match any files

rm -rf venv/
