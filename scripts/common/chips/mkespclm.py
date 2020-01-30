# Python file to read *.clmvar and make ESP-r file from it
# This file reads all *.clmvar files, the clmvar file contains
# names of variables. These variable names are
# used to make json files with the actual weather data. This
# script reads json files names as given in *.clmvar and makes relevant ESP-r
# climate files. If a json file is not present for any climate
# parameter this is indicated by a 0 in the clmvar file
# Climate parameters for one day are expected only and the same
# data is repeated for all days in the ESP-r clm file i.e.
# ONLY ONE JSON FILE PER ENTRY IN EVERY *.clmvar FILE IS EXPECTED
# If more files are present only the first file is read

#################
### IMPORTANT ###
#################
# This script assumes that the following command has already been run
# ./chips -g -p i.e. get previous days information
# This script also assumes that all weather parameters are present in var2get
import os
import json
from datetime import *
from subprocess import call

clmvarfilesfound = False # error trap
for file in os.listdir("."):
  if file.endswith(".clmvar"):
    clmvarfilesfound = True  # error trap
    # W[climate parameter 0-5][hours 0-23] N is number of times it occurs
    W = [[] for y in range(6)]
    N = [[] for y in range(6)]

    print("\n ...working on " + file + "\n")
    handle = open(file,"r")
    count = len(open(file).readlines()) # error trap
    if(count != 6): # error trap
      print ("ERROR: number of lines in file " + file + " is not 6, not writing this climate file") # error trap
      break # error trap
    linenum = 0
    while True:
      line = handle.readline()
      if not line:
        break
      line = line.rstrip() # remove trailing newline
      clm_desc = ["dry bulb temperature","diffuse solar","direct solar","wind speed","wind direction","relative humidity"]

      # find data files that begin with this string
      if (line == "0"):
        print("WARNING: variable "+clm_desc[linenum]+" not present in "+file+", setting to 0")
      else:
        thisfilefound = False # error trap
        for file1 in os.listdir("."):
          if(file1.startswith(line)):
            thisfilefound = True
            print("Reading " + file1)
            with open(file1) as uglyjson:
              try:
                j = json.load(uglyjson)
                startDay=-1
                for items in j['data']:
                  tmpstr = items['timestamp']
                  val = items['value']
                  if ":" == tmpstr[-3:-2]:
                    tmpstr = tmpstr[:-3]+tmpstr[-2:] # remove last :
                    ts = datetime.strptime(tmpstr,'%Y-%m-%dT%H:%M:%S%z')
                    if startDay<0:
                      startDay=int(ts.strftime('%j'))
                    day=int(ts.strftime('%j'))-startDay
                    iind=day*24+ts.hour
                    try: 
                      W[linenum][iind] += val
                      N[linenum][iind] += 1
                    except IndexError:
                      W[linenum].append(val)
                      N[linenum].append(1)

                  else:
                    # File is probably empty
                    print ("WARNING: "+ file1 + " is probably empty")
                    sys.exit(1)
                endDay=int(ts.strftime('%j'))
              except ValueError as e:
                print ("WARNING: "+ file1 + " is not a valid json file -- setting "+clm_desc[linenum]+" to 0")
        if(not thisfilefound): # error trap
          print("WARNING: data file " + line + "... not found, setting "+clm_desc[linenum]+" to 0" ) # error trap
      linenum += 1

    print(" \n ...finished with " + file + "\n")
    handle.close()

    # now begin writing clm file
    newclmfile = os.path.splitext(file)[0] + ".clm.a"
    w_handle = open(newclmfile,"w+")
    s_year=datetime.strftime(ts,'%Y')
    w_handle.write('''*CLIMATE 2
# Col | Metric                   | Unit
#   1 | dry bulb temperature     | tenths deg C            
#   2 | diffuse horizontal solar | W/m**2                  
#   3 | direct normal solar      | W/m**2                  
#   4 | wind speed               | tenths m/s              
#   5 | wind direction           | deg clockwise from north
#   6 | relative humidity        | percent                 
#   dummy line                  
 unknown                # climate location
 '''+s_year+''',00.00,00.00   # year, latitude, longitude difference
 01,02,03,00,04,05,06,00,00,00    # columns for each metric
 1,365    # period (julian days)
''')

    dayper=0
    for day in range(1,366):
      w_handle.write("* day  " + str(day) + "\n")
      tmpstr = ""

      # Fill in days before our period with the first day from our period.
      if day<startDay:
        for t in range(0,24):
          for p in range(0,6):
            hour_value = 0
            if t>=len(N[p]): 
              hour_value=0
            elif(N[p][t] != 0):
              hour_value = W[p][t] / N[p][t]
            if(p == 0 or p == 3):
              hour_value = hour_value * 10
            hour_value = int(hour_value)
            tmpstr = str(hour_value)
            if(p != 5):
              tmpstr += ","
            w_handle.write(tmpstr)
          w_handle.write("\n")

      # Fill in days after our period with the last day from our period.
      elif day>endDay:
        for t in range(-24,0):
          for p in range(0,6):
            hour_value = 0
            if t<-len(N[p]): 
              hour_value=0
            elif(N[p][t] != 0):
              hour_value = W[p][t] / N[p][t]
            if(p == 0 or p == 3):
              hour_value = hour_value * 10
            hour_value = int(hour_value)
            tmpstr = str(hour_value)
            if(p != 5):
              tmpstr += ","
            w_handle.write(tmpstr)
          w_handle.write("\n")

      else:
        for t in range(0,24):
          for p in range(0,6):
            iind=dayper*24+t
            hour_value = 0            
            if t>=len(N[p]): 
              hour_value=0
            elif(N[p][iind] != 0):
              hour_value = W[p][iind] / N[p][iind]
            if(p == 0 or p == 3):
              hour_value = hour_value * 10
            hour_value = int(hour_value)
            tmpstr = str(hour_value)
            if(p != 5):
              tmpstr += ","
            w_handle.write(tmpstr)
          w_handle.write("\n")
        dayper += 1
    w_handle.close()

if(not clmvarfilesfound): # error trap
  print("WARNING: No ESP-r climate files written because no *.clmvar files found in this folder") # error trap




















##
