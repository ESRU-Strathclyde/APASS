import datetime
import os
import subprocess

# 1. If session_cookie is more than 1 hour old then get another cookie using ./chips script
# 2. Read the file session_cookie and return the cookie inside to calling function

def get_cookie():
  now = datetime.datetime.now()
  got_cookie_at = datetime.datetime.fromtimestamp(os.path.getmtime('session_cookie'))
  cookie_age = now - got_cookie_at
  cookie_age = cookie_age.total_seconds()
  tmpstr = str(cookie_age)
  if(cookie_age > 3500): # if is one hour old (with 100s factor of safety)
    subprocess.call(['./chips','-d'])

  # get cookie
  handle = open('session_cookie','r')
  cookies = handle.read()
  handle.close()
  cookies = cookies.strip()
  cookies = {'session':cookies}
  return cookies
