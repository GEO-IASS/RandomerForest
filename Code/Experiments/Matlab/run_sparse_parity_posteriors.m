%% Plot Sparse Parity Posterior Heat Maps 
% Trains RF, RerF, RerFdn, and Rotation RF on sparse parity and plots
% posterior heat maps for each classifier

%% Initialize parameters
close all
clear
clc

fpath = mfilename('fullpath');
rerfPath = fpath(1:strfind(fpath,'RandomerForest')-1);

rng(1);

load('Sparse_parity_transformations_data.mat','Xtrain','Ytrain')
load Random_matrix_adjustment_factor

Classifiers = {'rf' 'frc' 'frcr' 'rr_rf' 'rr_rfr'};

Transformations = {'Untransformed' 'Scaled' 'Outlier'};

dims = [2 5 10 15 25 50 100];
ntrials = 10;

xmin = -.5;
xmax = 1.5;
ymin = xmin;
ymax = xmax;
npoints = 50;
[xgv,ygv] = meshgrid(linspace(xmin,xmax,npoints),linspace(ymin,ymax,npoints));
Xpost.Untransformed = xgv(:);
Ypost.Untransformed = ygv(:);
Xpost.Scaled = Xpost.Untransformed*10^-5;
Ypost.Scaled = Ypost.Untransformed;
Xpost.Outlier = Xpost.Untransformed;
Ypost.Outlier = Ypost.Untransformed;


for i = 4:5
    p = dims(i);
    fprintf('p = %d\n',p)
    
    Zpost{i}.Untransformed = zeros(npoints^2,p-2);
    Zpost{i}.Scaled = Zpost{i}.Untransformed;
    Zpost{i}.Outlier = Zpost{i}.Untransformed;
      
    if p <= 5
        mtrys = [1:p ceil(p.^[1.5 2])];
    elseif p > 5 && p <= 25
        mtrys = ceil(p.^[0 1/4 1/2 3/4 1 1.5 2]);
    else
        mtrys = [ceil(p.^[0 1/4 1/2 3/4 1]) 5*p 10*p];
    end
    mtrys_rf = mtrys(mtrys<=p);

    for c = 1:length(Classifiers)
        fprintf('%s start\n',Classifiers{c})
        Params{i}.(Classifiers{c}).nTrees = 500;
        Params{i}.(Classifiers{c}).Stratified = true;
        Params{i}.(Classifiers{c}).NWorkers = 2;
        if strcmp(Classifiers{c},'rfr') || strcmp(Classifiers{c},...
                'rerfr') || strcmp(Classifiers{c},'frcr') || ...
                strcmp(Classifiers{c},'rr_rfr')
            Params{i}.(Classifiers{c}).Rescale = 'rank';
        elseif strcmp(Classifiers{c},'rfn') || strcmp(Classifiers{c},...
                'rerfn') || strcmp(Classifiers{c},'frcn') || ...
                strcmp(Classifiers{c},'rr_rfn')
            Params{i}.(Classifiers{c}).Rescale = 'normalize';
        elseif strcmp(Classifiers{c},'rfz') || strcmp(Classifiers{c},...
                'rerfz') || strcmp(Classifiers{c},'frcz') || ...
                strcmp(Classifiers{c},'rr_rfz')
            Params{i}.(Classifiers{c}).Rescale = 'zscore';
        else
            Params{i}.(Classifiers{c}).Rescale = 'off';
        end
        if strcmp(Classifiers{c},'rerfd')
            Params{i}.(Classifiers{c}).mdiff = 'node';
        else
            Params{i}.(Classifiers{c}).mdiff = 'off';
        end
        if strcmp(Classifiers{c},'rf') || strcmp(Classifiers{c},'rfr')...
                || strcmp(Classifiers{c},'rfn') || strcmp(Classifiers{c},'rfz') || ...
                strcmp(Classifiers{c},'rr_rf') || strcmp(Classifiers{c},'rr_rfr') || ...
                strcmp(Classifiers{c},'rr_rfn') || strcmp(Classifiers{c},'rr_rfz')
            Params{i}.(Classifiers{c}).RandomForest = true;
            Params{i}.(Classifiers{c}).d = mtrys_rf;
        else
            Params{i}.(Classifiers{c}).RandomForest = false;
            Params{i}.(Classifiers{c}).d = mtrys;
        end
        if strcmp(Classifiers{c},'rerf') || strcmp(Classifiers{c},'rerfr')...
                || strcmp(Classifiers{c},'rerfn') || strcmp(Classifiers{c},'rerfz') || ...
                strcmp(Classifiers{c},'rerfd')
            Params{i}.(Classifiers{c}).Method = 'sparse-adjusted';
            for j = 1:length(Params{i}.(Classifiers{c}).d)
                Params{i}.(Classifiers{c}).dprime(j) = ...
                    ceil(Params{i}.(Classifiers{c}).d(j)^(1/interp1(ps,...
                    slope,p)));
            end
        elseif strcmp(Classifiers{c},'frc') || strcmp(Classifiers{c},'frcr') || ...
                strcmp(Classifiers{c},'frcn') || strcmp(Classifiers{c},'frcz')
            Params{i}.(Classifiers{c}).Method = 'frc';
            Params{i}.(Classifiers{c}).nmix = 2;
        end
        if strcmp(Classifiers{c},'rr_rf') || strcmp(Classifiers{c},'rr_rfr') || ...
                strcmp(Classifiers{c},'rr_rfn') || strcmp(Classifiers{c},'rr_rfz')
            Params{i}.(Classifiers{c}).Rotate = true;
        end
        
        for t = 1:length(Transformations)
            fprintf('%s\n',Transformations{t})

            OOBError{i}.(Classifiers{c}).(Transformations{t}) = NaN(ntrials,length(Params{i}.(Classifiers{c}).d));
            OOBAUC{i}.(Classifiers{c}).(Transformations{t}) = NaN(ntrials,length(Params{i}.(Classifiers{c}).d));
            TrainTime{i}.(Classifiers{c}).(Transformations{t}) = NaN(ntrials,length(Params{i}.(Classifiers{c}).d));

            for trial = 1:ntrials
                fprintf('Trial %d\n',trial)

                % train classifier
                poolobj = gcp('nocreate');
                if isempty(poolobj)
                    parpool('local',Params{i}.(Classifiers{c}).NWorkers,...
                        'IdleTimeout',360);
                end

                tic;
                [Forest,~,TrainTime{i}.(Classifiers{c}).(Transformations{t})(trial,:)] = ...
                    RerF_train(Xtrain(i).(Transformations{t})(:,:,trial),...
                    Ytrain(i).(Transformations{t})(:,trial),Params{i}.(Classifiers{c}));

                % select best hyperparameter

                for j = 1:length(Params{i}.(Classifiers{c}).d)
                    Scores = rerf_oob_classprob(Forest{j},...
                        Xtrain(i).(Transformations{t})(:,:,trial),'last');
                    Predictions = predict_class(Scores,Forest{j}.classname);
                    OOBError{i}.(Classifiers{c}).(Transformations{t})(trial,j) = ...
                        misclassification_rate(Predictions,Ytrain(i).(Transformations{t})(:,trial),...
                        false);
                    if size(Scores,2) > 2
                        Yb = binarize_labels(Ytrain(i).(Transformations{t})(:,trial),Forest{j}.classname);
                        [~,~,~,OOBAUC{i}.(Classifiers{c}).(Transformations{t})(trial,j)] = ...
                            perfcurve(Yb(:),Scores(:),'1');
                    else
                        [~,~,~,OOBAUC{i}.(Classifiers{c}).(Transformations{t})(trial,j)] = ...
                            perfcurve(Ytrain(i).(Transformations{t})(:,trial),Scores(:,2),'1');
                    end
                end
                BestIdx = hp_optimize(OOBError{i}.(Classifiers{c}).(Transformations{t})(trial,:),...
                    OOBAUC{i}.(Classifiers{c}).(Transformations{t})(trial,:));
                if length(BestIdx)>1
                    BestIdx = BestIdx(end);
                end

                if strcmp(Forest{BestIdx}.Rescale,'off')
                    Phats{i}.(Classifiers{c}).(Transformations{t})(:,:,trial) ...
                        = rerf_classprob(Forest{BestIdx},...
                        [Xpost.(Transformations{t}),...
                        Ypost.(Transformations{t}),...
                        Zpost{i}.(Transformations{t})],'last');
                else
                    Phats{i}.(Classifiers{c}).(Transformations{t})(:,:,trial) ...
                        = rerf_classprob(Forest{BestIdx},...
                        [Xpost.(Transformations{t}),...
                        Ypost.(Transformations{t}),...
                        Zpost{i}.(Transformations{t})],...
                        'last',Xtrain(i).(Transformations{t})(:,:,trial));
                end
                
                save([rerfPath 'RandomerForest/Results/Sparse_parity_transformations_posteriors.mat'],'dims',...
                    'Phats','Xpost','Ypost','Zpost')
            end
        end
        fprintf('%s complete\n',Classifiers{c})
    end   
end