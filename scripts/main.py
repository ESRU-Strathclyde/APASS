#! /usr/bin/env python3

# ESRU 2020

# This is the back end simulation service for the APASS service. Once
# invoked, this program will run in an infinite loop until a fatal error
# occurs or the process is terminated. Simulation jobs, requested by the
# APASS front end, will be spawned as seperate processes in parallel.
# The process of checking jobs is termed a dispatch, and happens at 
# intervals determined by a command line argument. Communication between 
# the front and back ends is accomplished by an SQL database and a shared 
# directory tree, see documentation for details.

# Command line options:
# -h, --help  - displays help text
# -d, --debug - service prints debug information to standard out,
#               and jobs print debug information to "[jobID].log"
#               in the job folder (../jobs/job_[jobID]).

# Command line arguments:
# 1: path to shared folder
# 2: [optional] dispatch interval in seconds

import sys
from os.path import isfile,isdir,realpath,dirname,basename
from os import devnull,makedirs,chdir,kill,remove,rename
from subprocess import run,Popen,PIPE,STDOUT
from time import sleep,time
from multiprocessing import Process,Pipe
import re
from datetime import datetime
from shutil import copytree,copyfile,rmtree,move
from glob import glob
import signal
from mysql import connector
import ctypes
from setproctitle import setproctitle

### FUNCTION: runJob
# This runs a performance assessment on an ESP-r model. This should be run in a
# seperate process, otherwise errors will terminate the main script. If
# debugging is active, a log file will be written out to "[jobID].log". If the
# job fails due to an error, a file called "[jobID.err]" will be written out
# containing the error message.

def runJob(s_jobID,s_tarball,s_MD5,s_building,s_estate,s_simStart,s_simStop,s_PAM,b_debug,con,s_shareDir):

    setproctitle('APASS'+s_jobID)

    s_jobDir=getJobDir(s_jobID)
    if isdir(s_jobDir):
        rmtree(s_jobDir)
    makedirs(s_jobDir)
    chdir(s_jobDir)

    # Create a directory for the outputs.
    makedirs('outputs')

    # Create temporary directory.
    makedirs('tmp')

    curDateTime=datetime.now()
    if b_debug:
        f_log=open(s_jobID+'.log','w')
        s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
        f_log.write('*** JOB STARTED @ '+s_dateTime+' ***\nJobID: '+s_jobID+'\n')
    else:
        f_log=None

    ### FUNCTION: SIGTERMhandler
    # Terminate signal handler, calls jobError to ensure error output
    # is generated and uploaded.
    def SIGTERMhandler(signal,frame):
        jobError(s_jobID,'job recieved a terminate signal',15,b_debug,f_log,s_shareDir)

    signal.signal(signal.SIGTERM,SIGTERMhandler)

    # Send started signal.
    i_prgv=1
    con.send(i_prgv)

    # Model file path and extension.
    s_modelFile=s_shareDir+'/Models/'+s_tarball
    s_ext=s_tarball.split('.',1)[1]

    # Get model.
    if b_debug: f_log.write('Retrieving model file '+s_modelFile+'\n')

    # # If there is an MD5 checksum passed from the front end, get checksum of the model file and compare them.
    # # Wait up to 100 seconds for model to appear and checksums to match.  
    # if not s_MD5sum is None:
    #     if b_debug: f_log.write('Checking MD5 checksum ...\n')  
    #     if b_debug: f_log.write('Checksum from front end: '+s_MD5sum+'\n')
    #     s_MD5sum=s_MD5sum.strip()
    #     i_count=0
    #     s_modelMD5=''
    #     while True:
    #         try:
    #             s_modelMD5=run(['md5sum',s_modelFile],check=True,sdtout=PIPE,text=True).stdout.split()[0]
    #         except:
    #             pass            
    #         if b_debug:f_log.write('Local checksum: '+s_modelMD5+'\n')
    #         if s_modelMD5==s_MD5sum: break
    #         i_count+=1
    #         if i_count>10:            
    #             # Timeout.
    #             jobError(s_jobID,'Timeout while waiting for model file "'+s_model+'"',11,b_debug,f_log,s_shareDir)
    #         if b_debug: f_log.write('Checksum does not match, waiting ...\n')
    #         sleep(10)
    #     if b_debug: f_log.write('Checksum verified.\n')
    # else:
    #     if b_debug: f_log.write('MD5 checksum not found.\n')

    # Now get the model.
    try:
        copyfile(s_modelFile,'./'+s_tarball)
    except:
        # Error - cannot find model.
        jobError(s_jobID,'error retrieving model "'+s_tarball+'"',11,b_debug,f_log,s_shareDir)
    else:
        if s_ext=='zip':
            ls_extract=['unzip']
        elif s_ext=='tar' or s_ext=='tar.gz':
            ls_extract=['tar','-xf']
        elif s_ext=='xml':
            ls_extract=['../../scripts/common/gbXMLconv/gbXMLconv.sh']
        else:
            jobError(s_jobID,'unrecognised model archive format (.zip, .tar, .tar.gz and .xml (gbXML) supported)',16,b_debug,f_log,s_shareDir)
        try:
            run(ls_extract+[s_tarball],check=True)
            remove(s_tarball)
        except:
            jobError(s_jobID,'failed to extract model',16,b_debug,f_log,s_shareDir)
        
    # Move model into folder called "model".
    ls_dirs=[a for a in glob('./*') if not a=='./tmp' and not a=='./outputs' and isdir(a)]
    makedirs('model')
    if len(ls_dirs)==1:
    # One directory found, probably means the model directories are inside this.
        try:
            run(['mv','-t','model']+glob('./'+ls_dirs[0]+'/*'),check=True)
        except:
            jobError(s_jobID,'failed to extract model',16,b_debug,f_log,s_shareDir)
        rmtree(ls_dirs[0])
    else:
        try:
            run(['mv','-t','model']+ls_dirs,check=True)  
        except:
            jobError(s_jobID,'failed to extract model',16,b_debug,f_log,s_shareDir)

    # Find cfg file. Must be only one in the cfg directory.
    ls_cfg=glob('model/cfg/*.cfg')
    if len(ls_cfg)==0:
        jobError(s_jobID,'cfg file not found in model cfg directory',13,b_debug,f_log,s_shareDir)
    elif len(ls_cfg)>1:
        jobError(s_jobID,'more than one cfg file found in model cfg directory',14,b_debug,f_log,s_shareDir)
    s_cfg=ls_cfg[0]
    if b_debug: f_log.write('Building: '+s_building+'\nModel: '+s_modelFile+'\ncfg file: '+s_cfg+'\n\n')
    s_cfgdir=dirname(s_cfg)

    # Take estate "NUI Galway" to mean "NUIG".
    if s_estate=='NUI Galway': s_estate='NUIG'

    # If estate is "Challenger" or "NUIG", try running chips to get weather from BEMserver.
    if s_estate=='Challenger' or s_estate=='NUIG':
        if b_debug: f_log.write(s_estate+' estate detected, attempting to gather weather data from BEMserver ...\n')
        try:
            run('../../scripts/common/chips/get_H2G_clm.sh '+s_estate+' '+s_simStart+' '+s_simStop+' >tmp/chips.out 2>&1',shell=True,check=True)
        except:            
            if b_debug: f_log.write('Failed, will use weather data referenced in cfg file.\n\n')
        else:
            if b_debug: f_log.write('Done.\n')
            # Grab the climate file that we've created and dump it in the model/dbs folder.
            move('../../scripts/common/chips/'+s_estate+'.clm',s_cfgdir+'/../dbs/'+s_estate+'.clm')
            # Change the climate file reference in the model cfg file.
            run(['sed','-e','s/^\*\(std\)*clm .*$/*clm ..\/dbs\/'+s_estate+'.clm/','-i',s_cfg])            
            if b_debug: f_log.write('Climate file reference in cfg file changed to ../dbs/'+s_estate+'.clm\n\n')

    # If estate is "NUIG", and running a thermal comfort PAM, try running chips to get measured data for calibration.
    # i_calStatus: 
    #  -2 = no calibration attempted, no uncertainties
    #  -1 = no calibration attempted, estate not recognised
    #   0 = calibration success
    #   1 = error in chips (most likely data unavailable)
    #   2 = error in calibro
    #   3 = error in autocal
    #   4 = error in esp-query
    #   5 = error in service

    if s_estate=='NUIG' and (s_PAM=='ISO7730_thermal_comfort' or s_PAM=='CIBSE_thermal_comfort'):
        i_calStatus=0
        if b_debug: f_log.write(s_estate+' estate and thermal comfort PAM detected, attempting to calibrate with measured data ...\n')

        # Run esp-query.
        if b_debug: f_log.write('Runnung esp-query ...\n')
        try:
            output=run(['../../scripts/common/esp-query/esp-query.py',s_cfg,'tdfa_file','tdfa_timestep','tdfa_entities','uncertainties_file','number_presets'],check=True,stdout=PIPE,encoding='utf-8').stdout
        except:
            i_calStatus=4
            if b_debug: f_log.write('Failed.\n')
        else:
            if b_debug: f_log.write('Success.\n')

        # Check for uncertainties definition.
        if not i_calStatus:
            if b_debug: f_log.write('Checking for uncetainties ...\n')
            try:
                m=re.search(r'^uncertainties_file=(\S*)$',output,re.M)  
                if m.group(1)=='':
                    i_calStatus=-2
                    if b_debug: f_log.write('Not found, cannot calibrate.\n')
                elif isfile(s_cfgdir+'/'+m.group(1)):
                    if b_debug: f_log.write('Found.\n')
                else:
                    i_calStatus=5
                    if b_debug: f_log.write('Failed.\n')
            except:
                i_calStatus=5
                if b_debug: f_log.write('Failed.\n')

        # Check if the model has an existing tdfa file.
        if not i_calStatus:
            if b_debug: f_log.write('Checking for existing temporal data ...\n')
            try:
                m=re.search(r'^tdfa_file=(\S*)$',output,re.M)
                if m.group(1)=='':
                    is_tdfa=False
                    s_tdfaTimestep='1'
                    if b_debug: f_log.write('Not found.\n')
                elif isfile(s_cfgdir+'/'+m.group(1)):
                    is_tdfa=True
                    s_tdfaFile=s_cfgdir+'/'+m.group(1)
                    m=re.search(r'^tdfa_timestep=(\S*)$',output,re.M)
                    s_tdfaTimestep=m.group(1)
                    m=re.search(r'^tdfa_entities=(\S*)$',output,re.M)
                    s_tdfaEntities=m.group(1)
                    if b_debug: f_log.write('Found.\n')
                else:
                    i_calStatus=5
                    if b_debug: f_log.write('Failed.\n')
            except:
                i_calStatus=5
                if b_debug: f_log.write('Failed.\n')

        # Fetch data from BEMserver.
        if not i_calStatus:
            if b_debug: f_log.write('Fetching data from H2G platform ...\n')
            try:
                run('../../scripts/common/chips/get_H2G_cal.sh '+s_estate+' '+s_simStart+' '+s_simStop+' '+s_tdfaTimestep+' >tmp/chips.out 2>&1',shell=True,check=True)
            except:            
                i_calStatus=1
                if b_debug: f_log.write('Failed.\n\n')
            else:
                if b_debug: f_log.write('Success.\n')
        
        # Put data into tdfa.
        if not i_calStatus:
            if is_tdfa:
                if b_debug: f_log.write('Adding measured data to existing tdfa ...\n')
                try:
                    run(['../../scripts/common/autocal/createTdfa.py',s_estate,s_simStart,s_simStop,s_tdfaTimestep],check=True)
                    assert isfile(s_cfgdir+'/../dbs/measured_data.tdfa')
                except:
                    i_calStatus=3
                    if b_debug: f_log.write('Failed.\n\n')
                else:
                    if b_debug: f_log.write('Success.\n')
            else:
                if b_debug: f_log.write('Converting measured data to new tdfa ...\n')
                try:
                    run(['../../scripts/common/autocal/createTdfa.py',s_estate,s_simStart,s_simStop,s_tdfaTimestep],check=True)
                    assert isfile(s_cfgdir+'/../dbs/measured_data.tdfa')
                except:
                    i_calStatus=3
                    if b_debug: f_log.write('Failed.\n\n')
                else:
                    if b_debug: f_log.write('Success.\n')

        # Associate new tdfa with model.
        if not i_calStatus:
            if is_tdfa:
                if b_debug: f_log.write('Addding association to model ...\n')
                try:
                    res=run(['../../scripts/common/autocal/addCalAssociation.sh',s_estate,str(int(s_tdfaEntities)+1)],check=True,text=True,stdout=PIPE,stderr=STDOUT)
                except:
                    i_calStatus=3
                    if b_debug: 
                        f_log.write('Failed, output follows ...\n')
                        f_log.write(res.stdout)
                else:
                    if b_debug: f_log.write('Success.\n')
            else:
                if b_debug: f_log.write('Associating tdfa with model ...\n')
                try:
                    res=run(['../../scripts/common/autocal/associateTdfa.sh',s_estate],check=True,encoding='utf-8',stdout=PIPE,stderr=STDOUT)
                except:
                    i_calStatus=3
                    if b_debug: 
                        f_log.write('Failed, output follows ...\n')
                        f_log.write(res.stdout)
                else:
                    if b_debug: f_log.write('Success.\n')

        # Create a simulation preset.
        # First, detect how many existing presets.
        if not i_calStatus:
            if b_debug: f_log.write('Adding a simulation preset ...\n')
            try:
                m=re.search(r'^number_presets=(\S*)$',output,re.M)  
                if m.group(1)=='':
                    i_calStatus=5
                    if b_debug: f_log.write('Failed to find number of existing presets.\n')
                else:
                    s_numPresets=m.group(1)
                    i_numPresets=int(m.group(1))
                    assert i_numPresets>=0
                    if b_debug: f_log.write('... '+s_numPresets+' existing presets detected ...\n')
            except:
                i_calStatus=5
                if b_debug: f_log.write('Failed to find number of existing presets.\n')

        if not i_calStatus:
            try:
                s_presetName='H2Gcal'
                s_presetLetter=chr(ord('a')+i_numPresets)
                s_startup='5'
                s_simStartDayMonth=s_simStart[0:2]+' '+s_simStart[3:5]
                s_simStopDayMonth=s_simStop[0:2]+' '+s_simStop[3:5]
                if i_numPresets==0:
                    s_isExisting='false'
                else:
                    s_isExisting='true'
                res=run(['../../scripts/common/autocal/createSimulationPreset.sh',s_presetName,s_presetLetter,s_startup,s_tdfaTimestep,s_simStartDayMonth,s_simStopDayMonth,s_isExisting],check=True,encoding='utf-8',stdout=PIPE,stderr=STDOUT)
            except:
                i_calStatus=3
                if b_debug: 
                    f_log.write('Failed to add a preset, output follows ...\n')
                    f_log.write(res.stdout)
            else:
                if b_debug: f_log.write('Success.\n')

        # We should now be ready to calibrate.
        if not i_calStatus:
            if b_debug: f_log.write('Running calibration ...\n')
            try:
                res=run(['../../scripts/common/autocal/runCalibration.sh',s_estate,s_presetLetter],check=True,encoding='utf-8',stdout=PIPE,stderr=STDOUT)
            except:
                i_calStatus=2
                if b_debug: 
                    f_log.write('Failed, output follows ...\n')
                    f_log.write(res.stdout)
            else:
                if b_debug: f_log.write('Success.\n')

        # If calibration succesfull, use calibrated model for PAM, 
        # and copy calibro outputs to outputs folder.
        if not i_calStatus:
            s_cfg=s_cfg.rsplit('.')[0]+'_cal.cfg'
            copyfile(s_cfgdir+'/calibro_report.pdf','outputs/calibro_report.pdf')
            copyfile(s_cfgdir+'/calibro_report.json','outputs/calibro_report.json')

        if b_debug: f_log.write('\n')

    else:
        i_calStatus=-1

    if i_calStatus<0:
        s_calStatus='Not attempted'
    elif i_calStatus>0:
        s_calStatus='Failed'
    elif i_calStatus==0:
        s_calStatus='Successful'

    # Write report preamble.
    s_time=curDateTime.strftime('%H:%M')
    s_date=curDateTime.strftime('%d/%m/%y')
    if s_PAM=='ISO7730_thermal_comfort':
        s_PAMpreStr='BS EN ISO 7730 (2005)\\footnote{BS (2005) BS EN ISO 7730 Ergonomics of the thermal environment - Analytical determination and interpretation of thermal comfort using calculation of the PMV and PPD indices and local thermal comfort criteria. London: British Standards Institute.} thermal comfort'
    elif s_PAM=='visual_comfort':
        s_PAMpreStr='BS EN 12464-1 (2011)\\footnote{BS (2011) BS EN 12464-1 Light and lighting - Lighting of work places, Part 1: Indoor work places. London: British Standards Institute.} visual comfort'
    elif s_PAM=='indoor_air_quality':
        s_PAMpreStr='BS EN 15251 (2007)\\footnote{BS (2007) BS EN 15251 Indoor environmental input parameters for design and assessment of energy performance of buildings addressing indoor air quality, thermal environment, lighting and acoustics. London: British Standards Institute.} indoor air quality'
    elif s_PAM=='CIBSE_thermal_comfort':
        s_PAMpreStr='CIBSE (2018)\\footnote{CIBSE (2018) Environmental design, CIBSE Guide A. Suffolk: CIBSE Publications.} thermal comfort'        

    s=r'''Analysis parameters
\begin{addmargin}[0.5cm]{0cm}
Request time: '''+s_date+' @ '+s_time+''' \\\\
Estate: '''+s_estate+''' \\\\
Model: '''+s_building+''' \\\\
Assessment: '''+s_PAMpreStr+''' \\\\
Simulation period: '''+s_simStart+' to '+s_simStop+''' \\\\
Calibration: '''+s_calStatus+''' \\\\
\\end{addmargin}
'''
    f_preamble=open('tmp/preamble.txt','w')
    f_preamble.write(s)
    f_preamble.close()

    # Check assessment script exists.
    s_PAMscript='../../scripts/assessments/'+s_PAM
    if not isfile(s_PAMscript):
        jobError(s_jobID,'performance assessment script "'+s_PAMscript+'" not found',12,b_debug,f_log,s_shareDir)
    if b_debug: f_log.write('Performance assessment: '+s_PAM+'\nPerformance assessment script: '+s_PAMscript+'\n')

    # Assemble argument list, noting dummy cases.
    b_dummy=False
    if s_PAM=='wireframe':
        ls_args=['-d','tmp','-r','outputs/pic.jpg','-j','outputs/data.json',s_cfg]
        b_dummy=True
    else:
        s_tmpres='simulation_results'
        s_tmppdf='outputs/report.pdf'
        s_tmpdpdf='outputs/detailed_report.pdf'
        s_tmpjson='outputs/data.json'
        ls_simStart=s_simStart.split('/')
        ls_simStop=s_simStop.split('/')
        s_period='{:s}_{:s}_{:s}_{:s}_{:s}'.format(ls_simStart[0],ls_simStart[1],ls_simStop[0],ls_simStop[1],ls_simStart[2])
        ls_args=['-p',s_period,'-d','tmp','-f',s_tmpres,'-r',s_tmppdf,'-R',s_tmpdpdf,'-j',s_tmpjson,'-P','tmp/preamble.txt',s_cfg]

    # Set handler so that the PAM will be killed if the job is killed.
    libc = ctypes.CDLL("libc.so.6")
    def set_pdeathsig(sig = signal.SIGKILL):
        def callable():
            return libc.prctl(1, sig)
        return callable

    if b_debug: 
        f_log.write('calling performance assessment with command: '+' '.join([s_PAMscript]+ls_args)+'\n')

    # Send running signal.
    i_prgv=2
    con.send(i_prgv)

    # Run PAM.
    proc=Popen([s_PAMscript]+ls_args,stdout=PIPE,stderr=PIPE,preexec_fn=set_pdeathsig(signal.SIGKILL))

    # Read file tmp/progress.txt every second to keep track of progress.
    # Progress = ...
    # 1: job started
    # 2: starting PAM
    # 3: PAM checkpoint 1 (e.g. simulating)
    # 4: PAM checkpoint 2 (e.g. extracting results)
    # 5: PAM checkpoint 3 (e.g. post-processing results)
    # 6: PAM checkpoint 4 (e.g. further simulations)
    # 7: PAM checkpoint 5 (e.g. further post-processing)
    # 8: PAM generating reports
    # 9: uploading results
    # 0: job complete
    s_prg='tmp/progress.txt'
    i_prgp=i_prgv
    while proc.poll()==None:
        sleep(1)
        if isfile(s_prg):
            f_prg=open(s_prg,'r')
            i_prgv=int(f_prg.readline().strip())
            f_prg.close()
        if i_prgv>i_prgp:
            con.send(i_prgv)
            i_prgp=i_prgv

    # Final progress value.
    if isfile(s_prg):
        f_prg=open(s_prg,'r')
        i_prgv=int(f_prg.readline().strip())
        f_prg.close()
    if i_prgv>i_prgp:
        con.send(i_prgv)

    t_tmp=(proc.stdout.read(),proc.stderr.read())

    if b_debug:
        f_log.write('\nPerformance assessment finished, output follows:\n'+t_tmp[0].decode()+'\n')
    if proc.returncode!=0:
        jobError(s_jobID,'performance assessment failed, error output follows:\n'+t_tmp[1].decode()+'\n',proc.returncode,b_debug,f_log,s_shareDir)

    # Get performance flag.
    if not b_dummy:
        proc=Popen(['awk','-f','../../scripts/common/get_performanceFlag.awk','tmp/pflag.txt'],stdout=PIPE)
        t_tmp=proc.communicate()
        s_pFlag=t_tmp[0].decode().strip()
        if s_pFlag=='0':
            i_pFlag=0
        elif s_pFlag=='1':
            i_pFlag=1
        else:
            jobError(s_jobID,'Unrecognised compliance flag "'+s_pFlag+'"\n',18,b_debug,f_log,s_shareDir)

        # Write model and output URLs to JSON.
        run(['sed','-e','s/"report": "",/"report": "https:\/\/mae-esru.mecheng.strath.ac.uk\/liveservices\/h2g\/Results\/'+s_jobID+'\/report.pdf",/','-i',s_tmpjson])
        run(['sed','-e','s/"results libraries": ""/"results libraries": "https:\/\/mae-esru.mecheng.strath.ac.uk\/liveservices\/h2g\/Results\/'+s_jobID+'\/res.tar.gz"/','-i',s_tmpjson])

    # Upload job results.
    # Send uploading signal.
    i_prgv=9
    con.send(i_prgv)

    # If not a dummy PAM, create tarball of simulation results and model (because you need the model to view results).
    if not b_dummy:
        ls_simRes=glob('simulation_results.*')
        try:
            run(['tar','-czf','res.tar.gz','model']+ls_simRes,check=True)
        except:
            jobError(s_jobID,'Could not create simulation results tarball\n',18,b_debug,f_log,s_shareDir)
        else:
            run(['mv','-t','outputs','res.tar.gz'])
            run(['rm']+ls_simRes)

    # TEMPORARY
    # Overwrite report with detailed report.
    rename('outputs/detailed_report.pdf','outputs/report.pdf')

    if b_debug: f_log.write('Copying outputs to shared folder ...\n')
    s_DBjobDir=s_shareDir+'/Results/'+s_jobID
    try:
        rmtree(s_DBjobDir)
    except OSError:
        pass
    makedirs(s_DBjobDir)
    ls_outputs=glob('outputs/*')
    for s_output in ls_outputs:
        if b_debug: f_log.write('Copying '+basename(s_output)+' ...\n')
        if isfile(s_output):
            copyfile(s_output,s_DBjobDir+'/'+basename(s_output))
        elif isdir(s_output):            
            copytree(s_output,s_DBjobDir+'/'+basename(s_output))
        else:            
            jobError(s_jobID,'Could not copy file "'+s_output+'"\n',18,b_debug,f_log,s_shareDir)

    if b_debug: f_log.write('Done.\n')

    curDateTime=datetime.now()
    s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
    if b_debug: f_log.write('\n*** JOB FINISHED @ '+s_dateTime+' ***\n')
    if b_debug: f_log.close()

    # Upload log file to outputs folder if present.
    if b_debug:
        copyfile(s_jobID+'.log',s_DBjobDir+'/log.txt')

    # Send exit signal then performance flag.
    con.send(0)
    if b_dummy:
        # In dummy cases, just send a "compliant" signal.
        con.send(0)
    else:
        con.send(i_pFlag)

    # If job has got to this point, it was (hopefully) successful, so remove local job directory.
#    chdir('..')
#    rmtree(s_jobDir)

### END FUNCTION


### FUNCTION: jobError
# Writes an error file for a simulation job and exits with a fail code. If
# debugging is active, also writes the message to the log file. Adds a datetime
# stamp to all messages.
# Writes error to json and pdf as well (currently not active).

def jobError(s_jobID,s_message,i_errorCode,b_debug,f_log,s_shareDir):
    curDateTime=datetime.now()
    s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
    f=open(s_jobID+'.err','w')
    f.write(s_message+' @ '+s_dateTime)
    f.close()
    if b_debug: f_log.write('Error: '+s_message+' @ '+s_dateTime)

    # Error reports are no longer provided in the front end interface.
    # This functionality is commented for the time being.

# # Write error message into json and pdf.
#     f_json=open('outputs/data.json','w')
#     f_json.write('{"error": {\n'
#                  '  "datetime": "'+s_dateTime+'",\n'
#                  '  "code": "'+str(i_errorCode)+'",\n'
#                  '  "message": "'+s_message.replace('"','')+'"\n'
#                  '}}\n')
#     f_json.close()
#     s_pdf='outputs/report.tex'
#     f_pdf=open(s_pdf,'w')
#     f_pdf.write('\\nonstopmode\n\documentclass{report}\n\\begin{document}\n'+
#                 'The job did not successfully complete.\n'+
#                 'An error occured at '+s_dateTime+'.\n'+
#                 'Error message was:\n\n'+
#                 '\\begin{verbatim}\n'+
#                 s_message+'\n'+
#                 '\end{verbatim}\n\n'+
#                 '\end{document}')
#     f_pdf.close()
# #    run(['sed','-e',r's/\_/\\\_/g','-i',s_pdf])
#     f_pdfLog=open('pdflatex.out','w')
#     run(['pdflatex','-output-directory=outputs',s_pdf],stdout=f_pdfLog)
#     run(['pdflatex','-output-directory=outputs',s_pdf],stdout=f_pdfLog)
#     f_pdfLog.close()

#     # Copy results to shared folder.
#     if b_debug: f_log.write('Copying outputs to shared folder ...\n')
#     s_DBjobDir=s_shareDir+'/Results/'+s_jobID
#     try:
#         rmtree(s_DBjobDir)
#     except OSError:
#         pass
#     makedirs(s_DBjobDir)
#     copyfile('outputs/data.json',s_DBjobDir+'/data.json')
#     copyfile('outputs/report.pdf',s_DBjobDir+'/report.pdf')
#     if b_debug: f_log.write('Done.\n')    

    if b_debug: f_log.close()
    sys.exit(1)

### END FUNCTION


### FUNCTION: sleepTilNext
# Checks the time elapsed since startTime (obtained from time() built-in),
# compares it with r_interval, and sleeps for any remaining time.
def sleepTilNext(start_time,r_interval,b_debug):
    end_time=time()
    time_taken=end_time-start_time
    if b_debug: print("main.py: dispatch took "+'{:.2f}'.format(time_taken)+" seconds")
    if time_taken<r_interval:
        if b_debug: print('main.py: sleeping for '+'{:.2f}'.format(r_interval-time_taken)+' seconds')
        sleep(r_interval-time_taken)
    else:
        if b_debug: print("main.py: I'm late! I'm late!")

### END FUNCTION


### FUNCTION: getJobDir
# Takes the jobID and generates a job directory name from it.
# Creates a relative path from the location of this script,
# i.e. assumes that "../jobs" exists from the location of this script.
def getJobDir(s_jobID):
    s_jobDir=dirname(realpath(__file__))+'/../jobs/job_'+s_jobID
    return s_jobDir

### END FUNCTION


### FUNCTION: mainError
# Prints an error message from the main process to the screen and to the error log.
def mainError(s_msg,s_errlog):    
    curDateTime=datetime.now()
    s_dateTime=curDateTime.strftime('%a %d %b %X %Y')
    print('main.py warning @ '+s_dateTime+': '+s_msg)
    f_errlog=open(s_errlog+'_cur.txt','a')
    f_errlog.write(s_dateTime+': '+s_msg+'\n')
    f_errlog.close()

### END FUNCTION



        


def main():

    setproctitle('APASS')

    # Set defaults.
    r_interval=15
    b_debug=False
    i_failLimit=10

    # Set up PAM lookup table.
    ls_PAMs=['wireframe','ISO7730_thermal_comfort','visual_comfort','indoor_air_quality','CIBSE_thermal_comfort']

    # Parse command line.
    i_argCount=0
    for arg in sys.argv[1:]:
        if arg[0]=='-':
            # This is an option.
            if arg=='-h' or arg=='--help':
                print('''
main.py
This is the back end simulation service for the APASS service. Once
invoked, this program will run in an infinite loop until a fatal error
occurs or the process is terminated. Simulation jobs, requested by the
APASS front end, will be spawned as seperate processes in parallel.
The process of checking jobs is termed a dispatch, and happens at 
intervals determined by a command line argument. Communication between 
the front and back ends is accomplished by an SQL database and a shared 
directory tree, see documentation for details.

Usage:
./main.py -h
./main.py [-d] path-to-shared-folder [dispatch-interval]

Command line options:
-h, --help  - displays help text
-d, --debug - service prints debug information to standard out,
              and jobs print debug information to "[jobID].log"
              in the job folder (../jobs/job_[jobID]).

Command line arguments:
1: path to shared folder
2: [optional] dispatch interval in seconds (default 15)''')
                sys.exit(0)
            elif arg=='-d' or arg=='--debug':
                b_debug=True
            else:
                print('main.py error: unknown command line option "'+arg+'"')
                sys.exit(1)
        else:
            # This is an argument.
            i_argCount=i_argCount+1
            if i_argCount==1:
                s_shareDir=arg
                if s_shareDir[-1]=='/': s_shareDir=s_shareDir[:-1]
            elif i_argCount==2:
                try:
                    r_interval=float(arg)
                except ValueError:
                    print('main.py error: interval argument is not a number')
                    sys.exit(1)
    if i_argCount<1 or i_argCount>2:
        print('main.py error: script accepts 1 or 2 argument(s)')
        sys.exit(1)

    # Main program.

    curDateTime=datetime.now()
    s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
    if b_debug: print('main.py: SERVICE START @ '+s_dateTime)

    # Create dictionaries to hold all running processes and pipe connections.
    # They can be retrieved by job ID (string).
    dict_proc=dict()
    dict_pipe=dict()

    ### FUNCTION: killItWithFire
    # Kills a job with extreme prejudice. Sends a SIGKILL and erases the job directory.
    # This can be used if a job starts to look fishy.
    # Assumes that the job exists and is alive.
    def killItWithFire(s_jobID):
        proc=dict_proc[s_jobID]
        kill(proc.pid,signal.SIGKILL)
        rmtree(getJobDir(s_jobID))
        con,sender=dict_pipe[s_jobID]
        con.close()
        sender.close()
        del dict_proc[s_jobID]
        del dict_pipe[s_jobID]

    # Dispatch in infinite loop.
    i_failCount=0
    while True:
        curDateTime=datetime.now()
        s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
        if b_debug: print('main.py: --------------------\nmain.py: starting dispatch @ '+s_dateTime)
        # Get current time, to time how long dispatch takes.
        start_time=time()

        # Get SQL database IP from file.
        f_SQL=open('.SQL.txt','r')
        s_SQLIP=f_SQL.readline().strip()
        s_SQLuser=f_SQL.readline().strip()
        s_SQLpwd=f_SQL.readline().strip()
        s_SQLdbs=f_SQL.readline().strip()
        s_errlog=f_SQL.readline().strip()
        f_SQL.close()
        if b_debug: print('main.py: connecting to SQL database at IP '+s_SQLIP)

        # Connect to SQL database.
        try:
            cnx=connector.connect(user=s_SQLuser,
                password=s_SQLpwd,
                host=s_SQLIP,
                database=s_SQLdbs,
                connection_timeout=r_interval)
        except:
            mainError('failed to connect to SQL database, skipping dispatch',s_errlog)
            sleepTilNext(start_time,r_interval,b_debug)
            continue
        cursor=cnx.cursor(buffered=True)

        ### FUNCTION: sql_update
        # Updates the sql table with a new "result" value.
        def sql_update(i_update,i_jobID):
            try:
                cursor.execute("UPDATE results SET result = {:d} WHERE id = {:d}".format(i_update,i_jobID))
                cnx.commit()
            except:
                mainError('failed to update SQL database',s_errlog)
            else:
                if b_debug: print('main.py: successfully updated the SQL database')

        # Retrieve job list from SQL database.
        try:
            cursor.execute("SELECT id,sim_start,sim_stop,model,pam,result FROM results")
            query=cursor.fetchall()
        except:
            mainError('failed to query SQL database, skipping dispatch',s_errlog)
            sleepTilNext(start_time,r_interval,b_debug)
            continue
        else:
            if b_debug: print('main.py: successfully queried the SQL database')

        # Check for required actions on jobs
        for (i_jobID,s_simStart,s_simStop,i_model,i_PAM,i_progress) in query:

            # Retrieve model details.
            try:
                cursor.execute("SELECT tarball,name,estate,md5 FROM models WHERE id = "+str(i_model))
                model_query=cursor.fetchall()
            except:
                i_update=9
                print('main.py: !!! failed to retrieve model details !!!')
                sql_update(i_update,i_jobID)
                continue
            else:
                (s_tarball,s_building,i_estate,s_MD5)=model_query[0]

            # Retrieve estate name.
            try:
                cursor.execute("SELECT name FROM estates WHERE id = "+str(i_estate))
                model_query=cursor.fetchall()
            except:
                i_update=9
                print('main.py: !!! failed to retrieve estate name !!!')
                sql_update(i_update,i_jobID)
                continue
            else:
                (s_estate,)=model_query[0]

            # Lookup PAM.
            # 0 = wireframe
            # 1 = BS EN ISO 7730 thermal comfort
            # 2 = BS EN 12464-1 visual comfort
            # 3 = BS EN 15251 indoor air quality
            # 4 = CIBSE thermal comfort
            try:
                s_PAM=ls_PAMs[i_PAM]
            except:
                i_update=9
                sql_update(i_update,i_jobID)
                print('main.py: !!! PAM ID {:d} not recognised !!!'.format(i_PAM))
                continue

            # Check stage of this job.
            s_jobID=str(i_jobID)
            i_update=-1

            # i_update values:
            # 0: pending
            # 1: run requested
            # 11 - 19: running with progress indicator
            # 2: job failed
            # 3: job complete, compliant
            # 4: job complete, major problem
            # 5: job complete, minor problem
            # 6: job compelte, advisory(?)
            # 7: cancel requested
            # 8: cancelled
            # 9: job error

            if i_progress==None:
                print('main.py: !!! NoneType progress ID !!!')
                print('main.py:   jobID - '+s_jobID)
                print('main.py:   building - '+s_building)
                print('main.py:   performance assessment - '+s_PAM)

            elif i_progress==0:
                # Start a job - python multiprocessing.
                # Check that a job with this ID doesn't already exist.
                if s_jobID in dict_proc:
                    print('main.py: job with ID '+s_jobID+' already exists, this job will not be started')
                    i_update=1
                    sql_update(i_update,i_jobID)
                    continue

                if b_debug:
                    print('main.py: *** starting new job ***')
                    print('main.py:   jobID - '+s_jobID)
                    print('main.py:   building - '+s_building)
                    print('main.py:   performance assessment - '+s_PAM)

                # Open a unidirectional pipe (slave->master) so the process can communicate its status.
                con,sender=Pipe(False)
                proc=Process(target=runJob,name='jobID_'+s_jobID,args=(s_jobID,s_tarball,s_MD5,s_building,s_estate,s_simStart,s_simStop,s_PAM,b_debug,sender,s_shareDir))
                proc.start()
                # Put the process and pipe connections into a dictionary for later retrieval.
                dict_proc[s_jobID]=proc
                dict_pipe[s_jobID]=(con,sender)
                i_update=1

            elif i_progress==1 or (i_progress>10 and i_progress<20):

                # Check status of currently running job - python multiprocessing.

                if b_debug:
                    print('main.py: ### checking status of job ###')
                    print('main.py:   jobID - '+s_jobID)
                    print('main.py:   building - '+s_building)
                    print('main.py:   performance assessment - '+s_PAM)
                # Retrieve job and connection objects from dictionaries.
                if not s_jobID in dict_proc or not s_jobID in dict_pipe:
                    # Job says it is running, but it not registered.
                    # This probably means the service crashed and has been restarted.
                    # Restart the job ... unless there is a kill file in the job directory.
                    if b_debug: print('main.py:   jobID not registered')

                    if isfile(getJobDir(s_jobID)+'/kill.it'):
                        print('main.py: !!! kill file detected !!!')
                        i_update=9
                        sql_update(i_update,i_jobID)
                        continue                        

                    if b_debug: print('main.py: *** restarting job ***')

                    if s_jobID in dict_proc: del dict_proc[s_jobID]
                    if s_jobID in dict_pipe: del dict_pipe[s_jobID]
                    con,sender=Pipe(False)
                    proc=Process(target=runJob,name='jobID_'+s_jobID,args=(s_jobID,s_tarball,s_MD5,s_building,s_estate,s_simStart,s_simStop,s_PAM,b_debug,sender,s_shareDir))
                    proc.start()
                    # Put the process and pipe connections into a dictionary for later retrieval.
                    dict_proc[s_jobID]=proc
                    dict_pipe[s_jobID]=(con,sender)                    
                    continue

            # Check for an admin kill command (a file called "kill.it" in the job directory).
                if isfile(getJobDir(s_jobID)+'/kill.it'):
                    print('main.py: !!! kill file detected !!!')
                    killItWithFire(s_jobID)
                    i_update=9
                    sql_update(i_update,i_jobID)
                    continue

                proc=dict_proc[s_jobID]
                con,sender=dict_pipe[s_jobID]
                if proc.is_alive():
                    # Job is still alive, check its status.
                    i_tmp=-1
                    b_done=False
                    if b_debug: print('main.py:   job is alive')
                    while con.poll():
                        i_tmp=con.recv()
                        if not type(i_tmp)==int:
                            # Unexpected signal type.
                            i_tmp=None
                            break
                        if b_debug: print('main.py:   job gave signal "'+str(i_tmp)+'"')
                        if i_tmp==0:
                            b_done=True
                    if b_done:                        
                        # Exit signal recieved but job is still running.
                        # Wait half a second then check again.
                        sleep(0.5)
                        if proc.is_alive():
                            # This shouldn't really be possible, so something odd is going on.
                            # Kill the job just to be safe.
                            # TODO - maybe check outputs?
                            killItWithFire(s_jobID)
                            if b_debug: print('main.py: !!! job looked dodgy !!!')
                            i_update=9
                        elif proc.exitcode==0:
                            if i_tmp==0:
                                # Check if the performance flag is still in the pipe.
                                if con.poll():
                                    i_tmp=con.recv()
                                else:
                                    # This shouldn't be possible.
                                    if b_debug: print('main.py: !!! job didn\'t give performance flag !!!')
                                    i_update=9
                            if i_tmp==0: 
                                i_update=3 # compliant
                            elif i_tmp==1: 
                                i_update=5 # minor problem
                            elif i_tmp==2: 
                                i_update=4 # major problem
                            elif i_tmp==3: 
                                i_update=6 # advisory?
                            else:
                                # Unexpected performance flag.
                                # Again, this shouldn't really be possible.
                                if b_debug: print('main.py: !!! job gave unrecognised performance flag !!!')
                                i_update=9
                        else:
                            i_update=2
                        # Close pipe and remove dictionary entries.
                        sender.close()
                        con.close()
                        del dict_proc[s_jobID]
                        del dict_pipe[s_jobID]
                    elif i_tmp>0 and i_tmp<10:
                        # Job has updated
                        i_update=10+i_tmp
                    elif i_tmp==-1:
                        # No update from job
                        i_update=0
                    else:
                        # Unexpected signal from job - kill it with fire!
                        killItWithFire(s_jobID)
                        if b_debug: print('main.py: !!! job looked dodgy !!!')
                        i_update=9
                else:
                    # Job is dead, check exit code and make sure it gave the expected exit signal.
                    sender.close()
                    i_tmp=-1
                    b_done=False
                    if b_debug: print('main.py:   job is dead')
                    while con.poll():
                        try: 
                            i_tmp_prev=i_tmp
                            i_tmp=con.recv()
                        except EOFError:
                            # Trap this error to avoid crashing the service.
                            i_tmp=i_tmp_prev
                            break
                        if b_debug: print('main.py:   job gave signal "'+str(i_tmp)+'"')
                        if i_tmp==0:
                            b_done=True
                    con.close()
                    if b_done and proc.exitcode==0:                        
                        if i_tmp==0: 
                            i_update=3
                        elif i_tmp==1: 
                            i_update=5
                        elif i_tmp==2: 
                            i_update=4
                        elif i_tmp==3: 
                            i_update=6
                        else:
                            # Unexpected performance flag.
                            # This shouldn't really be possible.
                            if b_debug: print('main.py: !!! job gave unrecognised performance flag !!!')
                            i_update=9
                    elif proc.exitcode!=0:
                        i_update=2
                    else:
                        if b_debug: print('main.py: !!! job didn\'t give exit signal !!!')
                        i_update=9
                    # Remove dictionary entries.
                    del dict_proc[s_jobID]
                    del dict_pipe[s_jobID]

                if i_update==3 or i_update==4 or i_update==5 or i_update==6:
                    if b_debug: print('main.py: *** job complete ***')

                elif i_update==1:
                    if b_debug: print('main.py: *** job requested ***')

                elif i_update>10 and i_update<20:
                    if b_debug: print('main.py: *** job still running ***')

                elif i_update==2:
                    if b_debug: print('main.py: !!! job failed !!!')

            elif i_progress==7:
                # Cancel a job.
                if b_debug:
                    print('main.py: ### cancelling job ###')
                    print('main.py:   jobID - '+s_jobID)
                    print('main.py:   building - '+s_building)
                    print('main.py:   performance assessment - '+s_PAM)
                # Retrieve job and connection objects from dictionaries.
                if not s_jobID in dict_proc or not s_jobID in dict_pipe:
                    if b_debug: print('main.py:   jobID not registered')
                    if b_debug: print('main.py: *** non-existent job flagged as cancelled ***')
                    i_update=8
                    sql_update(i_update,i_jobID)
                    continue
                proc=dict_proc[s_jobID]
                con,sender=dict_pipe[s_jobID]
                if proc.is_alive():
                    # Job is still alive, terminate it.
                    if b_debug: print('main.py:   job is alive')
                    proc.terminate()
                    slept=0
                    b_zombie=False
                    while proc.is_alive():
                        sleep(0.1)
                        slept+=1
                        if slept>50:
                            mainError('process BPAsim'+s_jobID+' left zombified',s_errlog)
                            b_zombie=True
                            break
                    if not b_zombie: proc.join()
                    sender.close()
                    con.close()
                    del dict_proc[s_jobID]
                    del dict_pipe[s_jobID]
                    i_update=8
                    if b_debug: print('main.py: *** job cancelled ***')
                else:
                    # Job is dead, check exit code and make sure it gave the expected exit signal.
                    sender.close()
                    i_tmp=0
                    b_done=False
                    if b_debug: print('main.py:   job is dead')
                    while con.poll():
                        try: 
                            i_tmp_prev=i_tmp
                            i_tmp=con.recv()
                        except EOFError:
                            # Trap this error to avoid crashing the service.
                            i_tmp=i_tmp_prev
                            break
                        if b_debug: print('main.py:   job gave signal "'+str(i_tmp)+'"')
                        if i_tmp==4:
                            b_done=True
                    con.close()
                    if b_done and proc.exitcode==0:
                        if i_tmp==0: 
                            i_update=3
                        elif i_tmp==1: 
                            i_update=5
                        elif i_tmp==2: 
                            i_update=4
                        elif i_tmp==3: 
                            i_update=6
                        else:
                            # Unexpected performance flag.
                            # This shouldn't really be possible.
                            if b_debug: print('main.py: !!! job gave unrecognised performance flag !!!')
                            i_update=9
                    elif proc.exitcode!=0:
                        i_update=2
                    else:
                        if b_debug: print('main.py: !!! job didn\'t give exit signal !!!')
                        i_update=9
                    # Remove dictionary entries.
                    del dict_proc[s_jobID]
                    del dict_pipe[s_jobID]

                    if i_update==3 or i_update==4 or i_update==5 or i_update==6:
                        if b_debug: print('main.py: *** job complete ***')

                    elif i_update==2:
                        if b_debug: print('main.py: !!! job failed !!!')
            
            # Update sql database with new job status.
            if i_update>0:
                sql_update(i_update,i_jobID)

        cnx.close()

        # Check that dispatch has not been running for longer than the interval.
        sleepTilNext(start_time,r_interval,b_debug)

if __name__=='__main__': main()
