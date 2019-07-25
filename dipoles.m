FilesList = dir([pathName,'*.set']);

%Load one dataset into EEGLAB. This is necessary for the
%EEG.chanlocs afterwards (until line 231)
if ~exist('startPointScript', 'var') || strcmp(startPointScript,'Yes')
    
    %Search for Head Model (HM): Standard and cortex. The latter is
    %actually used for atlas-to-dipole area assignation. The first is just
    %used for co-registration of electrodes on headmodel --> not needed
    %here, already done in Brainstorm.
    if ~contains(FilesList(1).name, 'Dipoles.set')
        [stdHeadModel, stdHeadModelPath] = uigetfile('*.mat','Look for standard head model',strcat(eeglabFolder, 'plugins', slashSys, 'dipfit', slashSys, 'standard_BEM', slashSys, 'standard_vol.mat'));
    end
    folderHM = strcat([uigetdir(cd,'Choose folder containing subjects head models for cortex or brainstem *** IN .MAT FORMAT ***'), slashSys]);
    FilesListHM = dir([folderHM,'*.mat']);
    
    %Search for standard electrode for 10-20 system
    % Exchanged for "chanLocFileELC" [stdElectrodes, stdElectrodesPath] = uigetfile('*.elc','Look for channel locations file',strcat(eeglabFolder, 'plugins', slashSys, 'dipfit', slashSys, 'standard_BEM', slashSys, 'elec', slashSys, 'standard_1020.elc'));
    
    if ~contains(FilesList(1).name, 'Dipoles.set')
        %Search for MRI anatomy folder of subjects
        subjAnatFolder = [uigetdir(folderHM,'Choose folder containing subjects anatomy *** IN .HDR / .IMG FORMAT ***'), slashSys];
        subjAnat = dir([subjAnatFolder, '*.hdr']);
        
        %Search for channel locations folder of subjects
        chanLocFolder = [uigetdir(subjAnatFolder,'Choose folder containing subjects channel locations *** IN BOTH .ELC AND .XYZ FORMAT ***'), slashSys];
        chanLocFilesXYZ = dir([chanLocFolder, '*.xyz']);
        chanLocFilesELC = dir([chanLocFolder, '*.elc']);
    end
    
    atlasComput = questdlg('Which atlas will be used for dipole fitting?', ...
        'Choose atlas', ...
        'Desikan-Killiany','Automated Anatomical Labeling','Desikan-Killiany');
    if isempty(atlasComput)
        error('Must choose atlas');
    else
        fprintf('Will use the %s atlas', atlasComput);
        if strcmp(atlasComput, 'Desikan-Killiany')
            atlasAcronym = '_DKA';
        elseif strcmp(atlasComput, 'Automated Anatomical Labeling')
            atlasAcronym = '_ALL2';
        end
    end
    
    brainComput = questdlg('Will you compute cortical or subcortical areas?', ...
        'Choose brain part', ...
        'Cortical','Subcortical','Cortical');
    if strcmp(brainComput, 'Cortical')
        folderAtlas = strcat(folderAtlas, 'Cortex', slashSys);
    elseif strcmp(brainComput, 'Subcortical')
        folderAtlas = strcat(folderAtlas, 'Brainstem', slashSys);
    end
    
    if ~contains(FilesList(1).name, 'Dipoles.set') && ( ~istrue(size(FilesList,1) == 2*size(FilesListHM,1)) || ~istrue(size(FilesList,1) == 2*size(subjAnat,1)) || ~istrue(size(FilesList,1) == 2*size(chanLocFilesXYZ,1)) || ~istrue(size(FilesList,1) == 2*size(chanLocFilesELC,1)) )
        warning('HAVE FOUND MISMATCH BETWEEN NUMBER OF DATASETS AND NUMBER OF HEAD MODELS, ANATOMY OR CHANNEL LOCATION FILES!')
    elseif contains(FilesList(1).name, 'Dipoles.set') && ~istrue(size(FilesList,1) == 2*size(FilesListHM,1))
        warning('HAVE FOUND MISMATCH BETWEEN NUMBER OF DATASETS AND NUMBER OF HEAD MODELS FILES!')
    end
    
end

if exist(folderDipoles, 'dir') ~= 7
    mkdir (folderDipoles);
end
if exist(folderAtlas, 'dir') ~= 7
    mkdir (folderAtlas);
end

cyclesRunDipfit = 0;
cyclesRunAtlas = 0;
realFilenumDecimal = 1;

uiwait(msgbox('Starting script after closing this window...'));

for Filenum = 1:numel(FilesList) %Loop going from the 1st element in the folder, to the total elements
    
    %This avoids exporting anatomy files for same subjects twice
    %for each dataset. realFilenum will be used for calling the
    %head models, mri and channel locations.
    realFilenum = floor(realFilenumDecimal);
    
    %Extract the base file name in order to append extensions afterwards
    fileNameComplete = char(FilesList(Filenum).name);
    if contains(FilesList(Filenum).name,'Placebo')
        fileName = fileNameComplete(1:(conservedCharacters+3));
    else
        fileName = fileNameComplete(1:conservedCharacters);
    end
    
    newFileName = strcat(fileName, '_Dipoles.set');
    
    %This avoids re-running ICA on datasets that ICA has already been run on.
    existsFile = exist ([folderDipoles, newFileName], 'file');
    
    %This is important because EEGLAB after completing the task leaves some windows open.
    close all;
    eeglabDeployed = 0;
    
    if existsFile ~= 2 && ~contains(FilesList(Filenum).name, 'Dipoles.set') %double condition
        %is necessary since fileName and existsFile will not match
        
        ALLCOM = {};
        ALLEEG = [];
        CURRENTSET = 0;
        EEG = [];
        [ALLCOM ALLEEG EEG CURRENTSET] = eeglab;
        
        %This is used in order to not reopen EEGLAB (and delete current
        %EEG variable) if the above if-end section has been entered.
        eeglabDeployed = 1;
        
        EEG = pop_loadset('filename',fileNameComplete,'filepath',pathName);
        [ALLEEG, EEG, CURRENTSET] = eeg_store( ALLEEG, EEG, 0 );
        
        %Set channel locations based on export from Brainstorm
        %after "fiducialing". Should be saved as Matlab .xyz file.
        %"'rplurchanloc',1" overwrites channel location info with
        %newly provided information
        % *** Please confirm that settings make sense!!! ***
        EEG=pop_chanedit(EEG, 'rplurchanloc',1,'load',[],'load',{[chanLocFolder, chanLocFilesXYZ(realFilenum).name] 'filetype' 'autodetect'},'setref',{'1:128' 'average'});
        [ALLEEG EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);
        EEG = eeg_checkset( EEG );
        
        %Compute dipoles on all components of ICA (EEG.icaact),
        %threshold of residual variance set to 100% in order to
        %compute ALL dipoles. Otherwise,
        %EEG.dipfit.model.areadk will not store area
        %information of dipole from atlas of dipolesabove
        %threshold.
        EEG = pop_dipfit_settings( EEG, 'hdmfile',[stdHeadModelPath, stdHeadModel],'coordformat','MNI','mrifile',[subjAnatFolder, subjAnat(realFilenum).name],'chanfile',[chanLocFolder, chanLocFilesELC(realFilenum).name],'chansel',[1:EEG.nbchan] );
        %EEG = pop_dipfit_settings( EEG, 'hdmfile',[folderHM, FilesListHM(realFilenum).name],'coordformat','MNI','mrifile',[subjAnatFolder, subjAnat(realFilenum).name],'chanfile',[chanLocFolder, chanLocFilesELC(realFilenum).name],'chansel',[1:EEG.nbchan] );
        [ALLEEG EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);
        %The next line assigns areas to the dipoles because the functions
        %calls for the Desikan-Killiany atlas for the DEFAULT HEAD MODEL
        %AND CORTEX. This will later be replaced by the code that calls for
        %the atlas computation.
        EEG = pop_multifit(EEG, [1:size(EEG.icaweights,1)] ,'threshold',100,'plotopt',{'normlen' 'on'});
        [ALLEEG EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);
        
        %Save this step since it takes such a long time. Atlas computations
        %saved as different datasets.
        EEG = pop_editset(EEG, 'setname', newFileName);
        EEG = eeg_checkset( EEG );
        EEG = pop_saveset( EEG, 'filename',newFileName,'filepath',folderDipoles);
        EEG = eeg_checkset( EEG );
        
        cyclesRunDipfit = cyclesRunDipfit + 1;
        
    end
    
    previousFileName = newFileName;
    if contains(fileNameComplete, 'Dipoles.set')
        newFileName = strcat(extractBefore(newFileName, '_Dipoles.set'), atlasAcronym, '.set');
    else
        newFileName = strcat(insertBefore(newFileName, '.set', atlasAcronym));
    end
    
    %This avoids re-running ICA on datasets that ICA has already been run on.
    existsFile = exist ([folderAtlas, newFileName], 'file');
    
    if existsFile ~= 2
        
        if eeglabDeployed == 0
            ALLCOM = {};
            ALLEEG = [];
            CURRENTSET = 0;
            EEG = [];
            [ALLCOM ALLEEG EEG CURRENTSET] = eeglab;
            
            if contains(FilesList(Filenum).name, 'Dipoles.set')
                EEG = pop_loadset('filename',FilesList(Filenum).name,'filepath',pathName);
            else
                EEG = pop_loadset('filename',previousFileName,'filepath',folderDipoles);
            end
            [ALLEEG, EEG, CURRENTSET] = eeg_store( ALLEEG, EEG, 0 );
        end
        
        if strcmp(atlasComput, 'Desikan-Killiany')
            %Calling for Desikan-Killiany dipole-to-area assignation.
            %This atlas only computes cortical areas!
            desikan_killiany_atlas
        elseif strcmp(atlasComput, 'Automated Anatomical Labeling')
            %call for AAL atlas. The structure of the head models of the
            %brainstem and the cortex exported from brainstorm have the
            %same structure: Atlas(2).Scouts(:).Vertices or .Label and are
            %appliable to cortex and to brainstorm area asignation of the
            %dipoles.
            autom_anat_labeling
        else
            warning('dipole area asignation has NOT been updated after calling pop_multifit');
        end
        
        %EEG.dipfit.model.posXYZ will now contain the updated areas for
        %each dipole (according to set threshold)
        EEG = eeg_checkset( EEG );
        EEG = pop_editset(EEG, 'setname', newFileName);
        EEG = eeg_checkset( EEG );
        EEG = pop_saveset( EEG, 'filename',newFileName,'filepath',folderAtlas);
        EEG = eeg_checkset( EEG );
        
        cyclesRunAtlas = cyclesRunAtlas + 1;
        
    end
    
    realFilenumDecimal = realFilenumDecimal + 0.5;
    
end
close all;