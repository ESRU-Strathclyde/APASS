#! /usr/bin/env python3

# This script takes a csv file of measured data (output from ../chips/get_H2G_cal.sh) and adds this data to an existing ESP-r tdfa.
# Currently, functionality is hard coded per estate ('Challenger' and 'NUIG').
# Assumes that current directory is a job directory with a model in it, and file "../chips/measured_data.csv" exists from script location.

import sys
import os
import datetime

# Read command line input.
estate=sys.argv[1]
dateS=sys.argv[2]
ts=datetime.datetime.strptime(dateS,'%d/%m/%Y')
s_csvStartJDay=ts.strftime('%j')
i_csvStartJDay=int(s_csvStartJDay)
dateF=sys.argv[3]
tf=datetime.datetime.strptime(dateF,'%d/%m/%Y')
s_csvEndJDay=tf.strftime('%j')
i_csvEndJDay=int(s_csvEndJDay)
s_csvYear=tf.strftime('%Y')
s_nsteps=sys.argv[4]
i_nsteps=int(s_nsteps)
s_oldTdfa=sys.argv[5]

# Initialise.
scriptPath=os.path.dirname(__file__)
i_startup=5 # this should match value in PAMs
os.rename(s_oldTdfa,s_oldTdfa+'_bkup')
s_newTdfa=s_oldTdfa
s_oldTdfa=s_oldTdfa+'_bkup'

# Calculate periods.
i_numDays_csv =i_csvEndJDay-i_csvStartJDay+1
i_numDays_tdfa=i_csvEndJDay-i_csvStartJDay+1+i_startup

# If estate not recognised, exit.
if estate!='NUIG': sys.exit(1)

# Open files.
f_oldTdfa=open(s_oldTdfa,'r')
f_newTdfa=open(s_newTdfa,'w')
f_csv=open(scriptPath+'/../chips/measured_data.csv','r')

if estate=='NUIG':

    # Get first day of csv data.
    i_line=0
    ll_firstDay=[]
    ll_lastDay=[]
    for s_line in f_csv:
        i_line+=1
        if i_line==1: continue
        ls_line=s_line.strip().split(',')
        t=datetime.datetime.strptime(ls_line[0],'%Y-%m-%d %H:%M:%S')
        r_time=float(t.strftime('%j'))+(float(t.strftime('%H'))+1.0+(float(t.strftime('%M'))/60.0))/24.0
        ll_firstDay.append([r_time]+ls_line[1:])
        if i_line==24*i_nsteps+1: break
    f_csv.seek(0)

    # Loop over lines in the old tdfa.
    data=False
    pointers=False
    i1_line=0
    i0_dataLine=-1
    for s_line in f_oldTdfa:
        i1_line+=1
        ls_line=s_line.strip().split(',')

        if i1_line==3:
            ls_line=s_line.strip().split()
            s_numItems=str(int(ls_line[1])+1)
            s_tdfaNsteps=ls_line[2]
            assert s_tdfaNsteps==s_nsteps
            s_year=s_csvYear
            i_tdfaStartJDay=int(ls_line[4])
            if i_tdfaStartJDay>(i_csvStartJDay-i_startup):
                print('Error: start day of existing tdf is not early enough')
                sys.exit(1)
            s_tdfaStartJDay=str(i_tdfaStartJDay)
            i_tdfaEndJDay=int(ls_line[5])
            if i_tdfaEndJDay<(i_csvEndJDay):
                print('Error: end day of existing tdf is not late enough')
                sys.exit(1)
            s_tdfaEndJDay=str(i_tdfaEndJDay)
            i_numCols=int(ls_line[6])+1
            s_numCols=str(i_numCols)
            f_newTdfa.write(' '.join([s_numCols,s_numItems,s_nsteps,s_year,s_tdfaStartJDay,s_tdfaEndJDay,s_numCols])+'\n')

        elif i1_line==5:
            ls_line=s_line.strip().split()
            s_numTS=ls_line[2]
            f_newTdfa.write(' '.join(['1',str(i_numCols+1),s_numTS])+'\n')

        elif ls_line[0]=='*pointers': 
            f_newTdfa.write('''*items
*tag,mixed_air   
*type,DBTZNOBS
*menu,Zone db T (observed):           
*aide,Observed zone DB temp               
*other,   0   1
*fields, 1
REAL  1   1      0.000    -49.000     49.000  Obs Zn DB temperature (C):        
*end_item
''')
            f_newTdfa.write(s_line)
            pointers=True

        elif pointers:
            f_newTdfa.write(','.join(ls_line+[str(int(ls_line[-1])+1)])+'\n')
            pointers=False

        elif s_line[:12]=='# Time Col 1':
            f_newTdfa.write(s_line)
            data=True
            f_csv.readline()
            i_jDay=i_tdfaStartJDay-1

        elif data:
            if ls_line[0]=='*end_tabular_data':
                f_newTdfa.write(s_line)
                break

            i0_dataLine+=1
            if i0_dataLine%(24*i_nsteps)==0: 
                i_jDay+=1
                i_hour=-1
            if i0_dataLine%(i_nsteps)==0:
                i_hour+=1
                i_minute=0
            else:
                i_minute=int(i_minute+60/i_nsteps)

            if i_jDay<i_csvStartJDay:
                if i_hour==0 and i_minute==0:
                    i0_firstDay=0
                else:
                    i0_firstDay+=1
                f_newTdfa.write(','.join(ls_line+ll_firstDay[i0_firstDay][1:])+'\n')

            elif i_jDay>=i_csvStartJDay and i_jDay<i_csvEndJDay:
                ls_csvLine=f_csv.readline().strip().split(',')
                f_newTdfa.write(','.join(ls_line+ls_csvLine[1:])+'\n')

            elif i_jDay==i_csvEndJDay:
                ls_csvLine=f_csv.readline().strip().split(',')
                ll_lastDay.append(ls_csvLine)
                f_newTdfa.write(','.join(ls_line+ls_csvLine[1:])+'\n')

            elif i_jDay>i_csvEndJDay:
                if i_hour==0 and i_minute==0:
                    i0_lastDay=0
                else:
                    i0_lastDay+=1
                f_newTdfa.write(','.join(ls_line+ll_lastDay[i0_lastDay][1:])+'\n')

        else:
            f_newTdfa.write(s_line)


f_oldTdfa.close()
f_newTdfa.close()
f_csv.close()
