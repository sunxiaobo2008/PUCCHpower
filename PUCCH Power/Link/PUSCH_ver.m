%% PUSCH 
close all;
clear;
clc;

%
path(path,'../Model');


%% Simulation Configuration

numSubframes = 100;                % Number of frames to simulate at each SNR
% SNRIn = [-4.1, -2.0, 0.1];  % SNR points to simulate
%  SNRIn = [-6.0, -5.0, -4.0,-3.0,-2.0,-1.0, 0.0];  % SNR points to simulate
% tmp = 2:-0.5:-2;
% SNRIn = tmp;
SNRIn = 30;%[-7.0:3.0:11.0];
DebugFlag = 0;
FoeCpCompFlag = 0;
FoeFineEstFlag = 0;

%% UE Configuration

ue.TotSubframes = 1; % set 1 when simulation
ue.NCellID = 1;     % Cell identity
% ue.RC = 'A3-2';      % FRC number
ue.RC = 'A3-1';      % FRC number

%% Propagation Channel Model Configuration

chcfg.NRxAnts = 2;               % Number of receive antenna
chcfg.DelayProfile = 'ETU';      % Delay profile
chcfg.DopplerFreq = 300.0;         % Doppler frequency    
chcfg.MIMOCorrelation = 'Low';   % MIMO correlation
chcfg.Seed = 65535;                % Channel seed    
chcfg.NTerms = 16;               % Oscillators used in fading model
chcfg.ModelType = 'GMEDS';       % Rayleigh fading model type 
chcfg.InitPhase = 'Random';      % Random initial phases
chcfg.NormalizePathGains = 'On'; % Normalize delay profile power
chcfg.NormalizeTxAnts = 'On';    % Normalize for transmit antennas

% HST config,scenario 1 & 3
%Parameter		Scenario 1	Scenario 3
%Ds               1000 m	300 m
%Dmin               50 m	2 m
%Velocity        350 km/h	300 km/h
%fd               1340 Hz	1150 Hz

% chcfg.Ds = 300;
% chcfg.Dmin = 2;
% chcfg.Velocity = 300;
% chcfg.DopplerFreq = 1150;

%% Channel Estimator Configuration
% Channel estimation settings are defined using a structure.

cec.FreqWindow = 13;              % Frequency averaging windows in REs
cec.TimeWindow = 1;               % Time averaging windows in REs
cec.InterpType = 'cubic';         % Interpolation type
cec.PilotAverage = 'UserDefined'; % Type of pilot averaging 
cec.Reference = 'Antennas';       % Reference for channel estimation

%% Uplink RMC Configuration

% Generate FRC configuration structure for A3-2
frc = lteRMCUL(ue);

rvSeq = [0 2 3 1];                     % the length is to constrait the trans num,
frc.PUSCH.RVSeq = rvSeq;

frc.NULRB = 100;

% bj: cofig para
% % frc.PUSCH.Modulation = 'QPSK'; % '64QAM';QPSK;16QAM
% frc.DuplexMode = 'TDD';
% frc.PUSCH.PRBSet = [10;10].';
% % frc.PUSCH.PRBSet = [0:24;0:24].';
% frc.PUSCH.PRBSet = [4:93;4:93].';
% frc.PUSCH.PRBSet = [25:49;25:49].';
% % frc.PUSCH.TrBlkSizes = [2216,2216,2216,2216,2216,2216,2216,2216,2216,2216];
%  frc.PUSCH.TrBlkSizes = [46888,46888,46888,46888,46888,46888,46888,46888,46888,46888];
%  frc.PUSCH.CodedTrBlkSizes = [57600,57600,57600,57600,57600,57600,57600,57600,57600,57600];
% frc.PUSCH.CodedTrBlkSizes = [86400,86400,86400,86400,86400,86400,86400,86400,86400,86400];
% frc.PUSCH.CodedTrBlkSizes = [7200,7200,7200,7200,7200,7200,7200,7200,7200,7200];
% % frc.PUSCH.CodedTrBlkSizes = [7200,7200,7200,7200,7200,7200,7200,7200,864,7200];
% Transport block sizes for each subframe within a frame
trBlkSizes = frc.PUSCH.TrBlkSizes;
codedTrBlkSizes = frc.PUSCH.CodedTrBlkSizes;




%% Setup HARQ Processes 
% Generate HARQ process table
noHarqProcesses = 8;
harqTable = mod(0:noHarqProcesses-1, noHarqProcesses)+1;  

%% Set Propagation Channel Model Sampling Rate

info = lteSCFDMAInfo(frc);
chcfg.SamplingRate = info.SamplingRate;     


%% Processing Loop
% Initialize variables used in the simulation and analysis
totalBLKCRC = zeros(numel(SNRIn), numSubframes);   % Total block CRC vector
bitThroughput = zeros(numel(SNRIn), numSubframes); % Total throughput vector
resultIndex = 1;        % Initialize frame counter index

% bj 
usersPUSCHpower = [0 6 -3 3];
usersNCellID = [1 150 150 3] ;
usersRNTI = [1 3  202 37] ;
userCyclicShift = [0 3 6 1];
userSeqGroup = [0 1  2 3];
ueChannelSeed = [ 2 7 200 500];

Sp = zeros(numSubframes,1);
Sp0 = zeros(numSubframes,1);
Spave = zeros(size(SNRIn));
Spstd = zeros(size(SNRIn));
Sp0ave = zeros(size(SNRIn));
Sp0std = zeros(size(SNRIn));

for nSNR = 1:length(SNRIn) %SNRdB = SNRIn
    
    % Calculate required AWGN channel noise
%     SNR = 10^(SNRdB/20);
    SNR = 10^(SNRIn(nSNR)/20);   
    % N is not normailized,when matlab original 
%     N = 1/(SNR*sqrt(double(info.Nfft)))/sqrt(2.0);   
    N = 1/SNR/sqrt(2.0);

    rng('default');
    
     fprintf('\nSimulating at %g dB SNR for a total %d SubFrame(s)', ...
        SNRIn(nSNR), numSubframes);
    
    % Store results for every subframe at SNR point
    bitTp = zeros(1,numSubframes);  % Intermediate bit throughput vector	
    blkCRC = zeros(1, numSubframes); % Intermediate block CRC vector         
    
    % Initialize state of all HARQ processes
    for i = 1:8
        harqProc(i) = hPUSCHNewHARQProcess( ...
            trBlkSizes(i), codedTrBlkSizes(i), rvSeq); %#ok
    end

    offsetused = 0;
    for subframeNo = 0:numSubframes-1%(NFrames*10-1)

        % Update subframe number
        frc.NSubframe = subframeNo;
        
        for user = 1:1
            frc.NCellID = usersNCellID(user);
            frc.CyclicShift = userCyclicShift(user);
            frc.RNTI = usersRNTI(user);
            frc.SeqGroup = userSeqGroup(user);
            
            
            % Get HARQ index for given subframe from HARQ index table
            harqIdx = harqTable(mod(subframeNo, length(harqTable))+1);
            
            % Update current HARQ process
            harqProc(harqIdx) = hPUSCHHARQScheduling(harqProc(harqIdx));
            frc.PUSCH.RV = harqProc(harqIdx).rvSeq(harqProc(harqIdx).rvIdx);
            frc.PUSCH.RVSeq = harqProc(harqIdx).rvSeq(harqProc(harqIdx).rvIdx);
            
            % load TB source data
%             tmpdata = load('A1.3_TB.mat');
%             harqProc(harqIdx).ulschTransportBlk = tmpdata.rxDecodedBits;
            
            % Create an SC-FDMA modulated waveform
            [txWaveform, txSubframe, RMCCFGOUT] = lteRMCULTool(frc, harqProc(harqIdx).ulschTransportBlk);
            txWaveform = txWaveform.*sqrt(double(info.Nfft));
            
            % Transmit an additional 25 samples at the end of the waveform to
            % cover the range of delays expected from the channel modeling
            %         txWaveform = [txWaveform; zeros(25, 1)]; %#ok
            
            % The initialization time for channel modeling is set each subframe
            % to simulate a continuously varying channel
            chcfg.InitTime = subframeNo/1000;
            
            % Pass data through channel model
            %         rxWaveform = lteFadingChannel(chcfg, txWaveform);
            
            % Add noise at the receiver
            %         v = N*complex(randn(size(rxWaveform)), randn(size(rxWaveform)));
            %         rxWaveform = rxWaveform+v;
            
            
            chcfg.Seed = ueChannelSeed(user);
            
            if (user==1)
                rxWaveform = lteFadingChannel(chcfg,[txWaveform*10^(usersPUSCHpower(user)/20); zeros(25,frc.NTxAnts)]);
%                 rxWaveform = lteHSTChannel(chcfg,[txWaveform*10^(usersPUSCHpower(user)/20); zeros(25,frc.NTxAnts)]);
                rxWaveform0 = rxWaveform;
            else
                rxWaveform = rxWaveform + ...
                    lteFadingChannel(chcfg,[txWaveform*10^(usersPUSCHpower(user)/20); zeros(25,frc.NTxAnts)]);
            end;
            
        end; % end of user
        
        % Add Noise at the receiver
        noise = N*complex(randn(size(rxWaveform)),randn(size(rxWaveform)));
        rxWaveform = rxWaveform + noise;

        % AWGN channel
%         rxWaveform = txWaveform + noise(1:30720,1);
        
        % baicells dsp data unit test
        if 0   
          dspdata = load('D:\1019 uldata\UL_SF2.txt');
          ul_data = dspdata(:,1) + 1j*dspdata(:,2);
          
          % freq offset compensation
%           foe1 = 900e3;
%           comp_phase = exp(-j*2*pi*foe1./(2048*15000).*(0:size(ul_data,1)-1));
%            ul_data = ul_data .*comp_phase.';
           
            rxWaveform = [ul_data;zeros(30,1)];
            rxWaveform0 = rxWaveform;  
        end;
        
        if DebugFlag
            %         figure();
            %         plot((1:size(rxWaveform,1)),abs(rxWaveform0(:,1)),'r');grid on;
            figure();
            plot((1:size(rxWaveform,1)),abs(rxWaveform(:,1)),'b');
            grid on;
        end;
        
        
         detindex = 1;           % which user to be detected
          frc.NCellID = usersNCellID(detindex);
            frc.CyclicShift = userCyclicShift(detindex);
            frc.RNTI = usersRNTI(detindex);
            frc.SeqGroup = userSeqGroup(detindex); 
            
          % load dsp data,unit test
        if 0  
        offsetused = 0;
%        dspdata = load('E:\�����ļ�\SF7_1RB_TD.mat');
        rxWaveform = [dspdata.Msf;zeros(30,1)];
        rxWaveform0 = rxWaveform;
        
        drs_pos = 2048*3+160+144*3+1;
        drs_index = [drs_pos:drs_pos+2048-1 drs_pos+15360:drs_pos+2048-1+15360];
        drs_td = rxWaveform0(drs_index);
        P_td = mean(drs_td.*conj(drs_td));    
        P_td_dB = 10*log10(P_td);    
         
        end;
        
        
        % Calculate synchronization offset
        offset = lteULFrameOffsetV2(frc, frc.PUSCH, rxWaveform,DebugFlag);
        if (offset < 25)
            offsetused = offset;
        end;
       
        
        
        % SC-FDMA demodulation
        rxSubframe = lteSCFDMADemodulateV2(frc, ...
            rxWaveform(1+offsetused:end, :));
         rxSubframe0 = lteSCFDMADemodulateV2(frc, ...
            rxWaveform0(1+offsetused:end, :));
        
        
           
        if FoeCpCompFlag
            % resturct TD data to estimate the big freq offset , [-7.5K 7.5K]
            %         [timeDomainSig,infoScfdma] = lteSCFDMAModulate(frc,rxSubframe);
            tmp_td =  rxWaveform(1+offsetused:offsetused+info.SamplingRate/1000, :);
            [freqoffset_cp] = FreOffsetEstimateCp(tmp_td,info,1);
            if mod(subframeNo,100)==0
                fprintf('\nFoeCp at SubFrame(s) %d is %f',subframeNo,freqoffset_cp);   
            end;
            
%             freqoffset_cp = 5000;            % unit test;
            % big freq offset compensation
            nts = 0:size(tmp_td,1)-1;
            Ts = 1e-6./30.72;
            comp = repmat(exp(-j*2*pi*freqoffset_cp*nts*Ts),[size(tmp_td,2),1]);
            tmp_td = tmp_td.*comp.';
            
            rxSubframe = lteSCFDMADemodulateV2(frc,tmp_td);
        end;
        % power normalize
%         rxSubframe = rxSubframe/sqrt(2048);
%         rxSubframe0 = rxSubframe0/sqrt(2048);
%         plot(abs(rxSubframe0(:,12)));
        
%
        if DebugFlag
            FDgrid = reshape(rxSubframe,[],1);


            figure();
            plot(abs(FDgrid));
            grid on;

            figure();
            semilogy(abs(FDgrid));
            grid on;

            drsindex = [frc.PUSCH.PRBSet(1,1)*12+1:(frc.PUSCH.PRBSet(end,1)+1)*12];
            pgrid = reshape(rxSubframe(drsindex,[4 11  ]),[],1);
            figure();
            scatter(real(pgrid),imag(pgrid));
            grid on;

            Pi = sum(abs(pgrid).*abs(pgrid))./size(pgrid,1);

        end;

        
        % Channel and noise power spectral density estimation
        [estChannelGrid, noiseEst, Hls] = lteULChannelEstimateV2(frc, ... 
            frc.PUSCH, cec, rxSubframe);
         [estChannelGrid0, noiseEst0, Hls0] = lteULChannelEstimateV2(frc, ... 
            frc.PUSCH, cec, rxSubframe0);
        
        % use Hls
        if 0
            estChannelGrid(drsindex,[1:7]) = (repmat(Hls(3,[1:300]),7,1)).';
            estChannelGrid(drsindex,[8:14]) = (repmat(Hls(3,[301:600]),7,1)).';
        end;
        
        if DebugFlag
            h = (ifft(estChannelGrid(drsindex,4)));
            figure();
            stem(abs(h));
            grid on;
            
            figure();
            plot(abs(estChannelGrid(:,4)));
            grid on;
            figure();
            plot(real(estChannelGrid(:,4)));
            grid on;
            figure();
            plot(imag(estChannelGrid(:,4)));
            grid on;
            figure();
            plot(abs(estChannelGrid(:,11)));
            grid on;
            
            figure();
            plot(abs(Hls(3,[1:300])));
            grid on;
        end;
        
        if FoeFineEstFlag            
            % TimeOffset and FreqOffset estimation
            drsindex = [frc.PUSCH.PRBSet(1,1)*12+1:(frc.PUSCH.PRBSet(end,1)+1)*12];
            [timeofset,freqoffset] = TimeFreqOffsetEstimate(estChannelGrid,drsindex);
            [snr] = PuschSinrEstimate(estChannelGrid,drsindex,noiseEst);
            if mod(subframeNo,100)==0
                fprintf('\nFoeFine and SINR at SubFrame(s) %d is %f , %f  \n',subframeNo,freqoffset,snr);   
            end;
        end;
        % Extract resource elements (REs) corresponding to the PUSCH from
        % the given subframe across all receive antennas and channel
        % estimates
        puschIndices = ltePUSCHIndices(frc, frc.PUSCH);
        [puschRx, puschEstCh] = lteExtractResources( ...
            puschIndices, rxSubframe, estChannelGrid);
         [puschRx0, puschEstCh0] = lteExtractResources( ...
            puschIndices, rxSubframe0, estChannelGrid0);
        
        % bj: calc power      
        if DebugFlag
            H = estChannelGrid(121:132,[4 11]);
            H0 = estChannelGrid0(121:132,[4 11]);
            %         figure();
            %         plot(abs(H(:,1)));
            Sp(subframeNo+1,1) = mean(mean(H.*conj(H)))/chcfg.NRxAnts;
            Sp0(subframeNo+1,1) = mean(mean(H0.*conj(H0)))/chcfg.NRxAnts;
            Sp_TD_liner = Sp*12/2048;
            Sp_TD_dB = 10*log10(Sp_TD_liner);
            Sp_TD_BB_dB = Sp_TD_dB+33;
        end;
                
        % MMSE equalization
        rxSymbols = lteEqualizeMMSE(puschRx, puschEstCh, noiseEst);
        
%         figure();
%         scatter(real(rxSymbols),imag(rxSymbols));

        % Update frc.PUSCH to carry complete information of the UL-SCH
        % coding configuration
        % bj: dsp data decode, unit test
%        
%         harqProc(harqIdx).trBlkSize = 4584;
        
        frc.PUSCH = lteULSCHInfo(frc, ...
            frc.PUSCH, harqProc(harqIdx).trBlkSize, 'chsconcat');

        % Decode the PUSCH        
        [rxEncodedBits,constellation] = ltePUSCHDecodeV2(frc, frc.PUSCH, rxSymbols);
        
        
        
        if DebugFlag            
            for symblo_index = 0:11
                figure();
                scatter(real(constellation(symblo_index*size(drsindex,2)+1:(symblo_index+1)*size(drsindex,2),1)),imag(constellation(symblo_index*size(drsindex,2)+1:(symblo_index+1)*size(drsindex,2),1)));
                grid on;
            end;
        end;
        
        % hard decision
%         HardBit = lteHardDecison(rxEncodedBits);
%         remod = lteSymbolModulate(HardBit,frc.PUSCH.Modulation);
%         
%         figure();
%         scatter(real(remod),imag(remod));
%         grid on;
        
        % Decode the UL-SCH channel and store the block CRC error for given
        % HARQ process harqIdx
        trBlkSize = trBlkSizes(mod(subframeNo, 10)+1);
        
        % bj:unit test
%         trBlkSize =  4584;
%           frc.PUSCH.RVSeq = 0;
%         frc.PUSCH.RV = 0;
        
        [rxDecodedBits, harqProc(harqIdx).crc, ...
            harqProc(harqIdx).decState] = lteULSCHDecode(...
            frc, frc.PUSCH, trBlkSize, ...
            rxEncodedBits, harqProc(harqIdx).decState);

        % Store the CRC calculation and total number of bits per subframe
        % successfully decoded
        blkCRC(subframeNo+1) = harqProc(harqIdx).crc;
        bitTp(subframeNo+1) = ...
            harqProc(harqIdx).trBlkSize.*(1-harqProc(harqIdx).crc);
        

    end;   % end of subframe     
    
    % Record the block CRC error and bit throughput for the total number of
    % frames simulated at a particular SNR
    totalBLKCRC(resultIndex, :) = blkCRC;
    bitThroughput(resultIndex, :) = bitTp;
    resultIndex = resultIndex + 1;
    
    % stat Sp and Sp0
    Spave(nSNR) = mean(Sp);
    Spstd(nSNR) = std(Sp,1,1);
    Sp0ave(nSNR) = mean(Sp0);
    Sp0std(nSNR) = std(Sp0,1,1);
    
    
end; % end of snrdB;


if 0
    figure();
    plot(SNRIn,Spave,'b-o',SNRIn,Sp0ave,'r-*');
    grid on;
    legend('real','ideal');
    xlabel('SNR (dB)');
    ylabel('liner mean power');
    title('PUSCH received average power');
    
    figure();
    plot(SNRIn,Spstd,'b-o',SNRIn,Sp0std,'r-*');
    grid on;
    legend('real','ideal');
    xlabel('SNR (dB)');
    ylabel('liner Std');
    title('PUSCH received Std');
    
end;



%% Display Throughput Results
% The throughput results are plotted as a percentage of total capacity and
% actual bit throughput for the range of SNR values input using
% <matlab:edit('hPUSCHResults.m') hPUSCHResults.m>.

% Throughput calculation as a percentage
throughput = 100*(1-mean(totalBLKCRC, 2)).';

residualBler = 1 - throughput/100;
figure();
semilogy(SNRIn,residualBler,'r-o');
title([ num2str(length(rvSeq))  'Tx residualBler for ', num2str(numSubframes) ' SubFrames']);
xlabel('SNR (dB)'); ylabel('residualBler');
grid on;
set(gca,  'XLim', [min(SNRIn) max(SNRIn)],'YLim', [0.001 1]);

hPUSCHResultsV2(SNRIn, numSubframes, trBlkSizes, throughput, bitThroughput);

displayEndOfDemoMessage(mfilename)


% UT, temp added
% throughput = 100*(1-mean(totalBLKCRC(:,[51:end]), 2)).';
% 
% residualBler = 1 - throughput/100;
% figure();
% semilogy(SNRIn,residualBler,'r-o');
% title([ num2str(length(rvSeq))  'Tx residualBler for ', num2str(numSubframes) ' SubFrames']);
% xlabel('SNR (dB)'); ylabel('residualBler');
% grid on;
% set(gca,  'XLim', [min(SNRIn) max(SNRIn)],'YLim', [0.001 1]);
% 
% hPUSCHResultsV2(SNRIn, numSubframes-50, trBlkSizes, throughput, bitThroughput(:,[51:end]));
