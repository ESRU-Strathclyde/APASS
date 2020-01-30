#! /usr/bin/env python3

# This script takes a csv file of measured data (output from ../chips/get_H2G_cal.sh) and creates an ESP-r tdfa from it.
# Currently, functionality is hard coded per estate ('Challenger' and 'NUIG').
# Assumes that current directory is a job directory with a model in it, and file "../chips/measured_data.csv" exists from script location.

import sys
import os
import datetime

# Read command line input.
estate=sys.argv[1]
dateS=sys.argv[2]
ts=datetime.datetime.strptime(dateS,'%d/%m/%Y')
ts_jDay=ts.strftime('%j')
dateF=sys.argv[3]
tf=datetime.datetime.strptime(dateF,'%d/%m/%Y')
tf_jDay=tf.strftime('%j')
s_nsteps=sys.argv[4]
i_nsteps=int(s_nsteps)

# Initialise.
scriptPath=os.path.dirname(__file__)
i_startup=5 # this should match value in PAMs

# Calculate periods.
i_numDays_csv =int(tf_jDay)-int(ts_jDay)+1
i_numDays_tdfa=int(tf_jDay)-int(ts_jDay)+1+i_startup

# If estate not recognised, exit.
if estate!='NUIG': sys.exit(1)

# Open files.
f_tdfa=open('model/dbs/measured_data.tdfa','w')
f_csv=open(scriptPath+'/../chips/measured_data.csv','r')

if estate=='NUIG':
  # Write tdfa header.
  f_tdfa.write('''ASCIITDF3   
# NWPR NITDF NTSPH itdyear,itdbdoy,itdedoy,columns
  1 1 '''+s_nsteps+' '+ts.strftime('%Y')+' '+str(int(ts_jDay)-i_startup)+' '+str(int(tf_jDay))+''' 1
# NEXTRC,NEXTCL,NDBSTP
  1 2 '''+str(i_numDays_tdfa*24*i_nsteps)+'''
*tdaid1,measured data from H2G platform
*tdaid2,-
*items
*tag,mixed_air   
*type,DBTZNOBS
*menu,Zone db T (observed):           
*aide,Observed zone DB temp               
*other,   0   1
*fields, 1
REAL  1   1      0.000    -49.000     49.000  Obs Zn DB temperature (C):        
*end_item
*pointers
 5
*tabular_data
# Time Col 1 Col 2 Col 3 Col 4 Col 5 Col 6 Col 7 Col 8...
''')

  # Get first day of csv data.
  i_line=0
  ll_firstDay=[]
  for s_line in f_csv:
    i_line+=1
    if i_line==1: continue
    ls_line=s_line.strip().split(',')
    t=datetime.datetime.strptime(ls_line[0],'%Y-%m-%d %H:%M:%S')
    r_time=float(t.strftime('%j'))+(float(t.strftime('%H'))+1.0+(float(t.strftime('%M'))/60.0))/24.0
    ll_firstDay.append([r_time]+ls_line[1:])
    if i_line==25: break
  
  # Write first day data for each start up day.
  for i_day in range(i_startup):
    for l_firstDay in ll_firstDay:
      r_time=l_firstDay[0]-float(i_startup-i_day)
      f_tdfa.write(','.join(['{:.6f}'.format(r_time)]+l_firstDay[1:])+'\n')
    
  # Write actual data.
  f_csv.seek(0)
  i_line=0
  for s_line in f_csv:
    i_line+=1
    if i_line==1: continue
    ls_line=s_line.strip().split(',')
    t=datetime.datetime.strptime(ls_line[0],'%Y-%m-%d %H:%M:%S')
    r_time=float(t.strftime('%j'))+(float(t.strftime('%H'))+1.0+(float(t.strftime('%M'))/60.0))/24.0
    f_tdfa.write(','.join(['{:.6f}'.format(r_time)]+ls_line[1:])+'\n')
  
f_tdfa.write('*end_tabular_data')
f_tdfa.close()
f_csv.close()
