#! /usr/bin/env python

# v2.1a ESRU 2017

# esp-query.py
# Script to query an ESP-r model for various data.
# "./esp-query.py -h" for help.


# FUNCTION getLine
# Get the nth line down in file f, return in list split by whitespace.
def getLine(f,n):
    for i in range(0,n):
        s_line=f.readline()
    s_line=s_line.strip()
    ls_line=s_line.split()
    return ls_line
# END FUNCTION


# FUNCTION get_zone_setpoints
# Scan control file for zone control setpoints.
def get_zone_setpoints(f_ctl,i_numDayTypes):
    
    s='zone_setpoints:'    
    s=s+'\n  number_of_calender_daytypes='+str(i_numDayTypes)
    i_numDayTypesInp=i_numDayTypes

    while True:
        ls_line=getLine(f_ctl,1)
        if ls_line[0:2]==['*','Building']:
            break
    
    ls_line=getLine(f_ctl,2)
    i_numFuncs=int(ls_line[0])
    s=s+'\n  number_of_functions='+str(i_numFuncs)

    for i_func in range(0,i_numFuncs):
        s=s+'\n  function#'+str(i_func+1)+':'
        ls_line=getLine(f_ctl,6)
        s_dayTypes=ls_line[0]
        if s_dayTypes=='0': 
            s_dayTypes='follows_calender'
            i_numDayTypes=i_numDayTypesInp
        elif s_dayTypes=='1': 
            s_dayTypes='all'
            i_numDayTypes=1
        else:
            sys.stderr.write('esp-query error: unrecognised daytypes flag: '+s_dayTypes+'\n')
            print(ls_line)
            sys.exit(1)
        s=s+'\n    day_types='+s_dayTypes

        for i_dayType in range(0,i_numDayTypes):
            if not s_dayTypes=='all':
                s=s+'\n    daytype#'+str(i_dayType+1)+':'
                xtra='  '
            else:
                xtra=''
            ls_line=getLine(f_ctl,1)
            s=s+'\n'+xtra+'    validity_start_day='+ls_line[0]
            s=s+'\n'+xtra+'    validity_end_day='+ls_line[1]
            ls_line=getLine(f_ctl,1)
            i_numPer=int(ls_line[0])
            #print(i_numPer)
            s=s+'\n'+xtra+'    number_of_periods='+str(i_numPer)

            for i_per in range(0,i_numPer):
                s=s+'\n'+xtra+'    period#'+str(i_per+1)+':'
                ls_line=getLine(f_ctl,1)
                s_ctlType=ls_line[1]
                #print(ls_line)
                if s_ctlType=='1':
                    s=s+'\n'+xtra+'      control_type=basic'
                elif s_ctlType=='2':
                    s=s+'\n'+xtra+'      control_type=none'
                elif s_ctlType=='11':
                    s=s+'\n'+xtra+'      control_type=match multi-sensor (ideal)'
# TODO - other ESP-r control types
                else:
#                    sys.stderr.write('esp-query error: unrecognised control type: '+s_ctlType+'\n')
#                    sys.exit(1)
                    ls_line=getLine(f_ctl,2)
                    continue
                s=s+'\n'+xtra+'      starting_at_hour='+ls_line[2]
                if s_ctlType=='2':
                    ls_line=getLine(f_ctl,1)
                else:
                    ls_line=getLine(f_ctl,2)
                    skip=False
                    if s_ctlType=='1':
                        i_hs=4
                        i_cs=5
                    elif s_ctlType=='11':
                        skip=True
# TODO - other ESP-r control types
                    if skip:
                        s=s+'\n'+xtra+'      heating_setpoint=n/a'
                        s=s+'\n'+xtra+'      cooling_setpoint=n/a'
                    else:
                        s=s+'\n'+xtra+'      heating_setpoint='+ls_line[i_hs]
                        s=s+'\n'+xtra+'      cooling_setpoint='+ls_line[i_cs]

    ls_line=getLine(f_ctl,2)
    s=s+'\n  function_zone_mappings='+ls_line[0]
    
    f_ctl.close()
    return s
# END FUNCTION


import sys,argparse
from os import path
from datetime import datetime

# OUTPUT MAPPINGS
# New outputs must be added here (also add help text in the parser below).
#            0            1              2             3                4                   5            6
ls_outputs=['model_name','number_zones','CFD_domains','zone_setpoints','model_description','zone_names','MRT_sensors',
#            7                  8                9           10               11            12            13
            'zone_floor_surfs','rad_viewpoints','rad_scene','zone_win_surfs','afn_network','ctm_network','number_ctm',
#            14               15                 16             17                 18                 19
            'afn_zone_nodes','afn_zon_nod_nums','zone_control','CFD_contaminants','CFD_domain_files','MRT_sensor_names',
#            20          21              22              23            24              25                   26
            'tdfa_file','tdfa_timestep','tdfa_startday','tdfa_endday','tdfa_entities','uncertainties_file','number_presets']
# Prerequisites.
#            0            1              2             3                4                   5            6
lli_needs= [[]          ,[]            ,[1,18]       ,[16]            ,[]                 ,[1]         ,[1]  ,
#            7                  8                9           10               11            12            13
            [1]               ,[]              ,[]         ,[1]             ,[]           ,[]           ,[12],
#            14               15                 16             17                 18                 19
            [11]            ,[11,14,1]         ,[]            ,[1,18]            ,[1]               ,[1,6]   ,
#            20          21              22              23            24              25                   26
            []         ,[20]           ,[20]           ,[20]         ,[20]           ,[]                  ,[] ]

# Argument parser and help text.
parser=argparse.ArgumentParser(description='Script to query an ESP-r model for various data.\n'
                                           'Assumes default model directory setup.\n'
                                           'Outputs will be written in the order that the identifiers are given.',
                               formatter_class=argparse.RawTextHelpFormatter)
parser.add_argument('-o','--output-file',
                    help='write outputs to OUTPUT_FILE instead of stdout')
parser.add_argument('CFG_FILE',
                    help='the .cfg file of the model to be queried')
parser.add_argument('OUTPUTS',
                    nargs='+',
                    choices=ls_outputs,
                    help='identifiers specifying the required outputs:\n'
                         ' model_name         = the name of the model\n'
                         ' number_zones       = the number of zones\n'
                         ' CFD_domains        = comma separated list of CFD indices for each zone:\n'
                         '                      0 - no CFD\n'
                         '                      1 - decoupled CFD\n'
                         '                      2 - coupled CFD\n'
                         ' CFD_domain_files   = comma separated list of CFD domain files for each zone\n'
                         ' CFD_contaminants   = for each CFD domain, comma separated list of contaminant names\n'
                         ' zone_control       = flag indicating if there is (1) or is not (0) zone control\n'
                         ' zone_setpoints     = heating and cooling setpoints of zone controls (currently basic only, blank if no zone control)\n'
                         ' model_description  = brief description of the model\n'
                         ' zone_names         = comma separated list of zone names\n'
                         ' MRT_sensors        = comma separated list of number of MRT sensors in each zone\n'
                         ' MRT_sensor_names   = for each zone, comma separated list of MRT sensor names\n'
                         ' zone_floor_surfs   = for each zone, comma seperated list of floor surface numbers\n'
                         ' rad_viewpoints     = comma seperated list of radiance viewpoint names for the first scene\n'
                         ' rad_scene          = name of the first radiance scene\n'
                         ' zone_win_surfs     = for each zone, comma separated list of window surface numbers\n'
                         ' afn_network        = name of the air flow network (blank if none defined)\n'
                         ' afn_zone_nodes     = comma separated list of afn node names representing zones (blank if no network defined, zone listed as 0 if not linked to a node)\n'
                         ' afn_zon_nod_nums   = comma separated list of afn node indices representing zones (blank if no network defined, zone listed as 0 if not linked to a node)\n'
                         ' ctm_network        = name of the contaminant network (blank if none defined)\n'
                         ' number_ctm         = number of contaminants in network (blank if no network defined)\n'
                         ' tdfa_file          = tdfa file referenced in cfg file (blank if none)\n'
                         ' tdfa_timestep      = time steps per hour in the tdfa file (blank if no tdfa file)\n'
                         ' tdfa_startday      = start day-of-year of tdfa data (blank if no tdfa file)\n'
                         ' tdfa_endday        = end day-of-year of tdfa data (blank if no tdfa file)\n'
                         ' tdfa_entities      = number of entities in tdfa file (blank if no tdfa file)\n'
                         ' uncertainties_file = uncertainty file referenced in cfg file (blank if none)\n'
                         ' number_presets     = number of simulation presets in cfg file\n')

# Parse command line.
args=parser.parse_args()
s_outputFile=args.output_file
s_inCfgFile=args.CFG_FILE
ls_inOutputs=args.OUTPUTS

# Open output file if required.
curDateTime=datetime.now()
s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
s='*** esp-query output for model "'+s_inCfgFile+'" @ '+s_dateTime+' ***\n'   
if s_outputFile: 
    f_output=open(s_outputFile,'w')
    f_output.write(s+'\n')
else:
    print(s)

# Set arrays for required outputs.
i_numOutputs=len(ls_outputs)
lb_outputs=[False]*i_numOutputs
lb_display=[False]*i_numOutputs
li_order=[0]*i_numOutputs
for i,s_output in enumerate(ls_outputs):
    if s_output in ls_inOutputs: 
        lb_outputs[i]=True
        lb_display[i]=True
        if len(lli_needs[i])>0:
            for i_need in lli_needs[i]:
                lb_outputs[i_need]=True
        li_order[i]=ls_inOutputs.index(s_output)
ls_outputVals=['']*i_numOutputs
ls_outputText=['']*len(ls_inOutputs)

# Get path to model files and open cfg file.
s_cfgPath,s_cfgFile=path.split(s_inCfgFile)
if s_cfgPath=='': s_cfgPath='.'
f_cfg=open(s_cfgPath+'/'+s_cfgFile,'r')

# Initialise.
if lb_outputs[5]: i_numZonesDone=0

# Scan cfg file.
i_countdown=-1
i_countdown2=-1
b_ctl=False
b_vwf=False
b_cfd=False
i_afn=0
i_numZonesDone=0
for s_line in f_cfg:
    s_line=s_line.strip()
    ls_line=s_line.split()

    if i_countdown>=0: i_countdown=i_countdown-1
    if i_countdown2>=0: i_countdown2=i_countdown2-1

    # Get model name.
    i_ind=0
    if lb_outputs[i_ind]:
        if ls_line[0]=='*root':
            s=ls_outputs[i_ind]+'='+ls_line[1]
            ls_outputVals[i_ind]=s
            lb_outputs[i_ind]=False

    # Get number of zones.
    i_ind=1
    if lb_outputs[i_ind]:
        if ls_line[0:2]==['*','Building']:
            i_countdown=2
        elif i_countdown==0:
            s=ls_outputs[i_ind]+'='+ls_line[0]
            ls_outputVals[i_ind]=s
            lb_outputs[i_ind]=False

    # Get model description.
    i_ind=4
    if lb_outputs[i_ind]:
        if ls_line[0:2]==['*','Building']:
            i_countdown2=1
        elif i_countdown2==0:
            s=ls_outputs[i_ind]+'='+' '.join(ls_line)
            ls_outputVals[i_ind]=s
            lb_outputs[i_ind]=False

    # Keep track of how many zones we've scanned and the zone index.
    # These should be the same.
    if ls_line[0]=='*zon':
        i_numZonesDone+=1
        s_zonInd=ls_line[1]
        assert int(s_zonInd)==i_numZonesDone

    # Get zone names.
    # Assumes that we already have number of zones.
    i_ind=5
    if lb_outputs[i_ind]:
        if ls_line[0]=='*geo':
            s_geo=s_cfgPath+'/'+ls_line[1]
            f_geo=open(s_geo,'r')
            s='#'
            while s[0]=='#':
                s=f_geo.readline()            
            f_geo.close()
            s=s.strip()
            s=s.split('#')[0]
            s_tmp=s.split()[0]
            if s_tmp=='*Geometry':
                # old geo file            
                s=s.split(',')[2]
            elif s_tmp=='GEN':
                # new geo file
                s=s.split()[1]
            else:
                sys.stderr.write('esp-query error: unrecognised format in file '+s_geo+'\n')
                sys.exit(1)
            s=s.strip()
            if i_numZonesDone==1:
                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+s
            else:
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+','+s
            if i_numZonesDone==int(ls_outputVals[lli_needs[i_ind][0]].split('=')[1]): lb_outputs[i_ind]=False

    # Get zone floor surface numbers.
    # Assumes that we already have number of zones.
    i_ind=7
    if lb_outputs[i_ind]:
        if ls_line[0]=='*geo':
            s_geo=s_cfgPath+'/'+ls_line[1]
            f_geo=open(s_geo,'r')
            s='#'
            while not s[0:10]=='*base_list':
                try:
                    s=f_geo.readline()
                    if s=='':
                        sys.stderr.write('esp-query error: could not find base list in file '+s_geo+'\n')
                        sys.exit(1)
                except:
                    sys.stderr.write('esp-query error: unrecognised format in file '+s_geo+'\n')
                    sys.exit(1)
            f_geo.close()
            s=s.strip()
            s=s.split('#')[0]
            ls=s.split(',')
            if ls[1]=='0':
                sys.stderr.write('esp-query warning: unable to find floor surface for zone '+str(i_numZonesDone)+'\n')
                s='0'
            else:
                s=','.join(ls[2:2+int(ls[1])])

            if i_numZonesDone==1: ls_outputVals[i_ind]=ls_outputs[i_ind]+':\n'
            ls_outputVals[i_ind]=ls_outputVals[i_ind]+'  zone#'+str(i_numZonesDone)+'='+s+'\n'
            if i_numZonesDone==int(ls_outputVals[lli_needs[i_ind][0]].split('=')[1]): lb_outputs[i_ind]=False

    # Get number of MRT sensors.
    # Assumes that we already have number of zones.
    i_ind=6
    if lb_outputs[i_ind]:
        if ls_line[0]=='*zon':
            b_vwf=True
        elif b_vwf and ls_line[0]=='*ivf':
            f_vwf=open(s_cfgPath+'/'+ls_line[1],'r')
            ls=getLine(f_vwf,5)
            f_vwf.close()
            s=ls[0]
            if i_numZonesDone==1:
                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+s
            else:
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+','+s
            if i_numZonesDone==int(ls_outputVals[lli_needs[i_ind][0]].split('=')[1]): lb_outputs[i_ind]=False

            # Get MRT sensor names.
            ii_ind=19
            if lb_outputs[ii_ind]:
                f_vwf=open(s_cfgPath+'/'+ls_line[1],'r')
                i=0
                i_countdown1=0
                i_countdown2=0
                active1=0
                active2=0
                ls2=[]
                j=0
                ls3=[]
                for s_line in f_vwf:
                    i+=1
                    if i_countdown1>0:
                        i_countdown1-=1
                        if i_countdown1==0: active1=1
                    if i_countdown2>0:
                        i_countdown2-=1
                        if i_countdown2==0: active2=1
                    if i==5:
                        ls=s_line.strip().split()
                        i_nsen=int(ls[0])
                        i_nsur=int(ls[1])
                    elif s_line.strip()=='*MRT_SENSOR':
                        i_countdown1=2
                    elif active1:
                        ls=s_line.strip().split()
                        ls2.append(ls[8])
                        if len(ls2)==i_nsen: 
                            break
                        active1=0
                    elif s_line.strip()=='*MRTVIEW':
                        i_countdown2=1
                    elif active2:
                        ls4=s_line.strip().split(',')
                        if ls4[-1]=='': 
                            ls4.pop()
                        ls3+=ls4
                        if len(ls3)==i_nsur:
                            ls3=[]
                            j+=1
                            if j==6: 
                                active1=1
                                active2=0
                                j=0

                f_vwf.close()
                s2=','.join(ls2)
                if i_numZonesDone==1: ls_outputVals[ii_ind]=ls_outputs[ii_ind]+':\n'
                ls_outputVals[ii_ind]=ls_outputVals[ii_ind]+'  zone#'+str(i_numZonesDone)+'='+s2+'\n'
                if i_numZonesDone==int(ls_outputVals[lli_needs[ii_ind][0]].split('=')[1]): lb_outputs[ii_ind]=False

            b_vwf=False

        elif b_vwf and ls_line[0]=='*zend':
            s='0'
            if i_numZonesDone==1:
                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+s
            else:
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+','+s
            if i_numZonesDone==int(ls_outputVals[lli_needs[i_ind][0]].split('=')[1]): lb_outputs[i_ind]=False

            ii_ind=19
            if lb_outputs[ii_ind]:
                s2=''
                if i_numZonesDone==1: ls_outputVals[ii_ind]=ls_outputs[ii_ind]+':\n'
                ls_outputVals[ii_ind]=ls_outputVals[ii_ind]+'  zone#'+str(i_numZonesDone)+'='+s2+'\n'
                if i_numZonesDone==int(ls_outputVals[lli_needs[ii_ind][0]].split('=')[1]): lb_outputs[ii_ind]=False

            b_vwf=False

    # Get CFD domain files.
    i_ind=18
    if lb_outputs[i_ind]:       
        if ls_line[0]=='*zon':
            b_cfd=True
        elif b_cfd and ls_line[0]=='*cfd':
            s=s_cfgPath+'/'+ls_line[1]
            if i_numZonesDone==1:
                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+s
            else:
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+','+s
            if i_numZonesDone==int(ls_outputVals[lli_needs[i_ind][0]].split('=')[1]): lb_outputs[i_ind]=False
            b_cfd=False
        elif b_cfd and ls_line[0]=='*zend':
            s=''
            if i_numZonesDone==1:
                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+s
            else:
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+','+s
            if i_numZonesDone==int(ls_outputVals[lli_needs[i_ind][0]].split('=')[1]): lb_outputs[i_ind]=False
            b_cfd=False

    # Get CFD domain indicators.
    i_ind=2
    if lb_outputs[i_ind]:  
        if not lb_outputs[lli_needs[i_ind][1]]:
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='
            s=''
            for s_cfd in ls_outputVals[lli_needs[i_ind][1]].split('=')[1].split(','):
                if len(s_cfd)==0:
                    s='0'
                else:
                    f_cfd=open(s_cfd,'r')
                    ls=getLine(f_cfd,2)
                    f_cfd.close()
                    if ls[1]=='0': s='1'
                    else: s='2'
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+s+','
            if len(s)>0: ls_outputVals[i_ind]=ls_outputVals[i_ind][:-1]
            lb_outputs[i_ind]=False

    # Get CFD contaminants.
    i_ind=17
    if lb_outputs[i_ind]:  
        if not lb_outputs[lli_needs[i_ind][1]]:
            ls_outputVals[i_ind]=ls_outputs[i_ind]+':\n'
            i_zn=0
            for s_cfd in ls_outputVals[lli_needs[i_ind][1]].split('=')[1].split(','):
                i_zn+=1
                if len(s_cfd)==0:
                    s=''
                else:
                    f_cfd=open(s_cfd,'r')
                    i_numContam=0
                    s=''
                    for s_cfdLine in f_cfd:
                        ls_cfdLine=s_cfdLine.strip().split()
                        if ls_cfdLine[0]=='*contaminants(':
                            i_numContam=int(ls_cfdLine[1])
                            if i_numContam==0: 
                                s='none'
                                break
                        elif i_numContam>0:
                            s=s+ls_cfdLine[0]+','
                            i_numContam-=1
                            if i_numContam==0:
                                s=s[:-1]
                                break
                    f_cfd.close()
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+'  zone#'+str(i_zn)+'='+s+'\n'
            lb_outputs[i_ind]=False

    # Get radiance viewpoint names.
    i_ind=8
    if lb_outputs[i_ind]:
        if ls_line[0]=='*rif':
            s_rcf=ls_line[1]
            f_rcf=open(s_cfgPath+'/'+s_rcf,'r')
            ls=getLine(f_rcf,5)
            f_rcf.close()
            assert ls[0]=='*rnm'
            f_rif=open(s_cfgPath+'/'+path.split(s_rcf)[0]+'/'+ls[1],'r')
            first=1
            for s_line in f_rif:
                ls=s_line.split()
                if ls[0]=='view=':
                    if first:
                        ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls[1]
                        first=0
                    else:                        
                        ls_outputVals[i_ind]=ls_outputVals[i_ind]+','+ls[1]
            f_rif.close()
            lb_outputs[i_ind]=False

    # Get radiance scene name.
    i_ind=9
    if lb_outputs[i_ind]:
        if ls_line[0]=='*rif':
            s_rcf=ls_line[1]
            f_rcf=open(s_cfgPath+'/'+s_rcf,'r')
            ls=getLine(f_rcf,7)
            f_rcf.close()
            assert ls[0]=='*srt'
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls[1]
            lb_outputs[i_ind]=False

    # Get window constructions.
    i_ind=10
    if lb_outputs[i_ind]:
        if ls_line[0]=='*geo':
            s_geo=s_cfgPath+'/'+ls_line[1]
            f_geo=open(s_geo,'r')
            s='#'
            while not s[0:5]=='*surf':
                try:
                    s=f_geo.readline()
                    if s=='':
                        sys.stderr.write('esp-query: could not find surfaces in file '+s_geo+'\n')
                        sys.exit(1)
                except:
                    sys.stderr.write('esp-query error: unrecognised format in file '+s_geo+'\n')
                    sys.exit(1)

            i_surf=0
            first=1
            if i_numZonesDone==1:
                ls_outputVals[i_ind]=ls_outputs[i_ind]+':\n'
            s2=s
            while True:
                i_surf+=1
                if s2[0:5]!='*surf': break
                s=s2.strip()
                s=s.split('#')[0]
                ls=s.split(',')
                s2=f_geo.readline()
                if ls[7]=='OPAQUE' or ls[8]!='EXTERIOR': continue
                s=str(i_surf)

                if first:
                    first=0
                    ls_outputVals[i_ind]=ls_outputVals[i_ind]+'  zone#'+str(i_numZonesDone)+'='+s
                else:
                    ls_outputVals[i_ind]=ls_outputVals[i_ind]+','+s    

            if first:
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+'  zone#'+str(i_numZonesDone)+'=none'

            ls_outputVals[i_ind]=ls_outputVals[i_ind]+'\n'

            if i_numZonesDone==int(ls_outputVals[lli_needs[i_ind][0]].split('=')[1]): 
                lb_outputs[i_ind]=False

            f_geo.close()

    # Get air flow network.
    i_ind=11
    if lb_outputs[i_ind]:
        if ls_line[0]=='*cnn':
            i_afn=1
        elif i_afn==1:
            if ls_line[0]=='0':
                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='
                lb_outputs[i_ind]=False
            elif ls_line[0]=='1':
                i_afn=2
                i_afntyp=1
            elif ls_line[0]=='3':
                i_afn=2
                i_afntyp=3
        elif i_afn==2:
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_line[0]
            lb_outputs[i_ind]=False

    # Get contaminant network.
    i_ind=12
    if lb_outputs[i_ind]:
        if ls_line[0]=='*ctm':
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_line[1]
            lb_outputs[i_ind]=False

    # Get number of contaminants.
    i_ind=13
    if lb_outputs[i_ind]:
        if not lb_outputs[lli_needs[i_ind][0]]:
            s_ctm=s_cfgPath+'/'+ls_outputVals[lli_needs[i_ind][0]].split('=')[1]
            f_ctm=open(s_ctm,'r')
            ls=getLine(f_ctm,5)
            f_ctm.close()
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls[0]
            lb_outputs[i_ind]=False

    # Get AFN zone node names.
    i_ind=14
    if lb_outputs[i_ind]:
        if not lb_outputs[lli_needs[i_ind][0]]:
            if i_afn==2:
                i_afn=3
            elif i_afn==3:
                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_line[0]
                i_afn+=1
            elif i_afn>3:
                ls_outputVals[i_ind]=ls_outputVals[i_ind]+ls_line[0]

    # Get AFN zone node indices.
    i_ind=15
    if lb_outputs[i_ind]:
        if i_afn>3:
            ls_afnNods=ls_outputVals[lli_needs[i_ind][1]].split('=')[1].split(',')
            s_afn=s_cfgPath+'/'+ls_outputVals[lli_needs[i_ind][0]].split('=')[1]
            f_afn=open(s_afn,'r')
            i_numNods=len(ls_afnNods)
            ls_nodNums=['0']*i_numNods
            ls_afnNods_tmp=ls_afnNods[:]
            if i_afntyp==1:
                i_nodNum=0
                for s_line2 in f_afn:
                    if s_line2[0:70]==' Node         Fld. Type   Height    Temperature    Data_1       Data_2':
                        i_nodNum=1
    #                elif s_line2[0:36]==' Component    Type C+ L+ Description':
    #                    sys.stderr.write('esp-query error: could not find all AFN zone nodes in network\n')
    #                    sys.exit(1)                    
                    elif i_nodNum:
                        ls_line2=s_line2.strip().split()
                        if ls_line2[0] in ls_afnNods_tmp:
                            ls_nodNums[ls_afnNods.index(ls_line2[0])]=(str(i_nodNum))
                            ls_afnNods_tmp.remove(ls_line2[0])
                            if len(ls_afnNods_tmp)==0:
                                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+','.join(ls_nodNums)
                                break
                        i_nodNum+=1
            elif i_afntyp==3:
                i_nodNum=1
                for s_line2 in f_afn:
                    if s_line2[0:5]=='*node':
                        ls_line2=s_line2.strip().split(',')
                        if ls_line2[1] in ls_afnNods_tmp:
                            ls_nodNums[ls_afnNods.index(ls_line2[1])]=(str(i_nodNum))
                            ls_afnNods_tmp.remove(ls_line2[1])
                            if len(ls_afnNods_tmp)==0:
                                ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+','.join(ls_nodNums)
                                break
                        i_nodNum+=1

            f_afn.close()

    # Get zone control flag.
    i_ind=16
    if lb_outputs[i_ind]:
        if ls_line[0]=='*ctl':
            s_ctl=s_cfgPath+'/'+ls_line[1]
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'=1'
            lb_outputs[i_ind]=False
        

    # Get zone control setpoints.
    i_ind=3
    if lb_outputs[i_ind]:
        if not lb_outputs[lli_needs[i_ind][0]] and ls_outputVals[lli_needs[i_ind][0]].split('=')[1]=='1':
            if ls_line[0]=='*list':
                i_numDayTypes=int(ls_line[1])
                f_ctl=open(s_ctl,'r')
                s=get_zone_setpoints(f_ctl,i_numDayTypes)
                ls_outputVals[i_ind]=s
                lb_outputs[i_ind]=False

    # Get tdfa file.
    i_ind=20
    if lb_outputs[i_ind]:
        if ls_line[0]=='*tdf':
            s_tdfa=s_cfgPath+'/'+ls_line[1]
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_line[1]
            lb_outputs[i_ind]=False

    # Get tdfa time step.
    i_ind=21
    if lb_outputs[i_ind]:
        if not lb_outputs[lli_needs[i_ind][0]]:
            f_tdfa=open(s_tdfa,'r')
            ls_tdfa=getLine(f_tdfa,3)
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_tdfa[2]
            lb_outputs[i_ind]=False
            f_tdfa.close()

    # Get tdfa start day.
    i_ind=22
    if lb_outputs[i_ind]:
        if not lb_outputs[lli_needs[i_ind][0]]:
            f_tdfa=open(s_tdfa,'r')
            ls_tdfa=getLine(f_tdfa,3)
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_tdfa[4]
            lb_outputs[i_ind]=False
            f_tdfa.close()

    # Get tdfa end day.
    i_ind=23
    if lb_outputs[i_ind]:
        if not lb_outputs[lli_needs[i_ind][0]]:
            f_tdfa=open(s_tdfa,'r')
            ls_tdfa=getLine(f_tdfa,3)
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_tdfa[5]
            lb_outputs[i_ind]=False
            f_tdfa.close()

    # Get number of tdfa entities.
    i_ind=24
    if lb_outputs[i_ind]:
        if not lb_outputs[lli_needs[i_ind][0]]:
            f_tdfa=open(s_tdfa,'r')
            ls_tdfa=getLine(f_tdfa,3)
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_tdfa[1]
            lb_outputs[i_ind]=False
            f_tdfa.close()

    # Get uncertainties file.
    i_ind=25
    if lb_outputs[i_ind]:
        if ls_line[0]=='*ual':
            s_ual=s_cfgPath+'/'+ls_line[1]
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_line[1]
            lb_outputs[i_ind]=False

    # Get number of simulation presets.
    i_ind=26
    if lb_outputs[i_ind]:
        if ls_line[0]=='*sps':
            ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+ls_line[1]
            lb_outputs[i_ind]=False


            

            

f_cfg.close()

# If any zone item booleans remain, add a null onto the end.
#for i_ind in [2,6]:
#    if lb_outputs[i_ind]:
#        if int(ls_outputVals[lli_needs[i_ind][0]].split('=')[1])==1:        
#            ls_outputVals[i_ind]=ls_outputs[i_ind]+'=0'
#        else:
#            ls_outputVals[i_ind]=ls_outputs[i_ind]+',0'
#        lb_outputs[i_ind]=False

# Function to add an entry if an item has not been found.
# if "entry" is not defined, will add a blank entry.
def addBlank(i_ind,s_entry=''):
    if lb_outputs[i_ind]:
        ls_outputVals[i_ind]=ls_outputs[i_ind]+'='+s_entry
        lb_outputs[i_ind]=False

addBlank(12)
addBlank(13)
if lb_outputs[14]:
    if ls_outputVals[14]=='':
        addBlank(14)
        if lb_outputs[15]: addBlank(15)
    else:
        lb_outputs[14]=False
        if lb_outputs[15]: lb_outputs[15]=False
        
if lb_outputs[lli_needs[3][0]]: addBlank(3)
addBlank(16,s_entry='0')
addBlank(20)
addBlank(21)
addBlank(22)
addBlank(23)
addBlank(24)
addBlank(25)
addBlank(26,s_entry='0')

# If any booleans remain, something has not been found - throw an error.
if True in lb_outputs:
    sys.stderr.write('esp-query error: some information could not be retrieved -\n')
    li_errors=[a for a,b in enumerate(lb_outputs) if b]
    for i in li_errors:
        sys.stderr.write(ls_outputs[i]+'\n')
    sys.exit(1)
else:
# Write output.
    for i,b in enumerate(lb_display):
        if b:
            ls_outputText[li_order[i]]=ls_outputVals[i]
    if s_outputFile:
        f_output.write('\n\n'.join(ls_outputText))
    else:
        print('\n\n'.join(ls_outputText))

