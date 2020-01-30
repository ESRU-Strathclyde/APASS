# Python file to read var2get and make csv file from it
# This file reads var2get file, which contains
# names of variables. These variable names are
# used to make json files with the actual data. This
# script reads json files names as given in var2get and makes a csv
# file from the data in the json.

#################
### IMPORTANT ###
#################
# This script assumes that the following command has already been run
# ./chips -g

# 1 Command line argument = number of time steps per hour.
import os
import json
import sys
from datetime import *
from subprocess import call

i_nsteps=int(sys.argv[1])

var2getfilefound = False # error trap
for file in os.listdir("."):
  if file == "var2get":
    var2getfilefound = True  # error trap
    # W[parameter][hour] sum of data per hour
    # N[parameter][hour] number of data items per hour
    W = []
    N = []

    print("\n ...working on " + file + "\n")
    handle = open(file,"r")
    varind=0
    varnames=[]
    nhours=0
    iyear=0
    for line in handle:
      line = line.strip()
      if line == "": continue # skip blank lines
      varname=line.split(',')[0]
      varnames.append(varname)

      # find data files that begin with this string
      thisfilefound = False # error trap
      for file1 in os.listdir("."):
        if(file1.startswith(varname)):
          thisfilefound = True
          print("Reading " + file1)
          with open(file1) as uglyjson:
            try:
              j = json.load(uglyjson)
            except ValueError:
              print ("WARNING: "+ file1 + " is not a valid json file")
              sys.exit(1)         
            W.append([])
            N.append([])
            startDay=-1
            for items in j['data']:
              tmpstr = items['timestamp']
              val = items['value']
              if ":" == tmpstr[-3:-2]:
                tmpstr = tmpstr[:-3]+tmpstr[-2:] # remove last :
                ts = datetime.strptime(tmpstr,'%Y-%m-%dT%H:%M:%S%z')
                if iyear==0: iyear=ts.year
                if startDay<0:
                  startDay=int(ts.strftime('%j'))
                day=int(ts.strftime('%j'))-startDay
                iind=day*24*i_nsteps+ts.hour*i_nsteps+int(ts.minute/(60/i_nsteps))
                try: 
                  W[varind][iind] += val
                  N[varind][iind] += 1
                except IndexError:
                  # In case of missing data, fill in gaps with 0s.
                  # This will be interpolated later.
                  while len(W[varind]) < iind:
                    W[varind].append(0)
                    N[varind].append(0)                  
                  W[varind].append(val)
                  N[varind].append(1)
              else:
                print ("WARNING: invalid data in file "+ file1)
                sys.exit(1)
            varind+=1
      if(not thisfilefound): # error trap
        print("WARNING: data file " + varname + "... not found") # error trap
        sys.exit(1)

    print(" \n ...finished with " + file + "\n")
    handle.close()

    # now begin writing csv file
    newcsvfile = "measured_data.csv"
    w_handle = open(newcsvfile,"w+")

    w_handle.write(','.join(['Time']+varnames)+'\n')
    dayOfYear=startDay-1
    for row in range(len(W[0])):
      if row%(24*i_nsteps)==0: 
        dayOfYear+=1
        hour=-1
      if row%(i_nsteps)==0:
        hour+=1
        minute=0
      else:
        minute+=60/i_nsteps
      day=dayOfYear-startDay
      ts=datetime.strptime('{:d} {:d} {:d} {:d}'.format(iyear,dayOfYear,hour,int(minute)),'%Y %j %H %M')
      tmpstr=ts.strftime('%Y-%m-%d %H:%M:%S')
      for WW,NN in zip(W,N):
        # If there's no value for this time row, interpolate.
        # Find previous and next time row with values.
        # Allow interpolation for 3 hours maximum, any more and throw an error.       
        if NN[row]==0:
          offset=0
          bval=None
          while boffset<3*i_nsteps and brow>0:
            boffset+=1
            brow=row-boffset
            if NN[brow]>0:
              bval=WW[brow]/NN[brow]
              break

          offset=0
          fval=None
          while foffset<3*i_nsteps and frow<(len(W[0])-1):
            foffset+=1
            frow=row+foffset
            if NN[frow]>0:
              fval=WW[frow]/NN[frow]
              break
          
          if bval and fval and (boffset+foffset)<=3*i_nsteps:
            rowrange=frow-brow
            valrange=fval-bval
            tmpstr=tmpstr+',{:.2f}'.format(bval+valrange*(boffset/rowrange))
          else:
            print("WARNING: missing data spanning more than 3 hours in file "+file1)
            sys.exit(1)
          
        else:
          tmpstr=tmpstr+',{:.2f}'.format(WW[row]/NN[row])
      w_handle.write(tmpstr+'\n')

    w_handle.close()

if(not var2getfilefound): # error trap
  print("WARNING: No csv file written because no var2get file found in this folder") # error trap




















##
