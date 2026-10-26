classdef FilterDesignerApp < matlab.apps.AppBase
% FilterDesignerApp  GA / PSO based FIR and IIR filter designer.
%   Run with:  FilterDesignerApp
%   Filter types : Low Pass, High Pass, Band Pass, Band Stop
%   Methods      : FIR (symmetric / linear phase), IIR (cascade of 2nd-order sections)
%   Optimizers   : GA, PSO
%   IIR stability: poles are parameterised in polar form with radius <= 0.98,
%                  so every candidate in every generation is stable by construction.
%                  The final denominator is additionally verified with roots().

    properties (Access = public)
        UIFigure
        TypeDD
        MethodDD
        OptDD
        FsEdit
        OrderEdit
        Fp1Edit
        Fp2Edit
        Fs1Edit
        Fs2Edit
        RpEdit
        AsEdit
        PopEdit
        GenEdit
        DelayEdit
        LblFp1
        LblFp2
        LblFs1
        LblFs2
        GenerateBtn
        StopBtn
        GenLabel
        InfoArea
        AxPZ
        AxMag
        AxCost
    end

    properties (Access = private)
        S = struct();
        StopFlag = false;
        SpecLines = gobjects(0);
        hZ
        hP
        hMag
        hCost
    end

    % ------------------------------------------------------------------
    methods (Access = public)
        function app = FilterDesignerApp
            createComponents(app);
            registerApp(app, app.UIFigure);
            onTypeChanged(app);
            onMethodChanged(app);
            app.UIFigure.Visible = 'on';
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end

    % ------------------------------------------------------------------
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible','off','Position',[40 40 1300 740], ...
                'Name','GA / PSO Filter Designer');
            app.UIFigure.CloseRequestFcn = @(~,~) delete(app);

            main = uigridlayout(app.UIFigure,[1 2]);
            main.ColumnWidth = {330,'1x'};
            main.RowHeight = {'1x'};

            left = uigridlayout(main,[18 2]);
            left.Layout.Row = 1; left.Layout.Column = 1;
            left.ColumnWidth = {150,'1x'};
            left.RowHeight = [repmat({26},1,16),{40},{'1x'}];
            left.RowSpacing = 5;

            addLabel(left,1,'Filter type');
            app.TypeDD = uidropdown(left,'Items',{'Low Pass','High Pass','Band Pass','Band Stop'}, ...
                'Value','Low Pass','ValueChangedFcn',@(~,~) app.onTypeChanged());
            app.TypeDD.Layout.Row = 1; app.TypeDD.Layout.Column = 2;

            addLabel(left,2,'Filter method');
            app.MethodDD = uidropdown(left,'Items',{'FIR','IIR'},'Value','FIR', ...
                'ValueChangedFcn',@(~,~) app.onMethodChanged());
            app.MethodDD.Layout.Row = 2; app.MethodDD.Layout.Column = 2;

            addLabel(left,3,'Optimizer');
            app.OptDD = uidropdown(left,'Items',{'GA','PSO'},'Value','PSO');
            app.OptDD.Layout.Row = 3; app.OptDD.Layout.Column = 2;

            addLabel(left,4,'Sampling freq Fs (Hz)');
            app.FsEdit = addNum(left,4,8000,[1 Inf]);
            app.FsEdit.ValueChangedFcn = @(~,~) app.onTypeChanged();

            addLabel(left,5,'Filter order');
            app.OrderEdit = addNum(left,5,40,[1 200]);
            app.OrderEdit.RoundFractionalValues = 'on';
            app.OrderEdit.ValueDisplayFormat = '%.0f';

            app.LblFp1 = addLabel(left,6,'Passband edge (Hz)');
            app.Fp1Edit = addNum(left,6,1000,[0 Inf]);
            app.LblFp2 = addLabel(left,7,'Passband edge 2 (Hz)');
            app.Fp2Edit = addNum(left,7,0,[0 Inf]);
            app.LblFs1 = addLabel(left,8,'Stopband edge (Hz)');
            app.Fs1Edit = addNum(left,8,1500,[0 Inf]);
            app.LblFs2 = addLabel(left,9,'Stopband edge 2 (Hz)');
            app.Fs2Edit = addNum(left,9,0,[0 Inf]);

            addLabel(left,10,'Passband ripple (dB)');
            app.RpEdit = addNum(left,10,1,[0.01 10]);
            addLabel(left,11,'Stopband atten (dB)');
            app.AsEdit = addNum(left,11,30,[10 120]);
            addLabel(left,12,'Population size');
            app.PopEdit = addNum(left,12,80,[10 500]);
            app.PopEdit.RoundFractionalValues = 'on';
            app.PopEdit.ValueDisplayFormat = '%.0f';
            addLabel(left,13,'Max generations');
            app.GenEdit = addNum(left,13,300,[1 5000]);
            app.GenEdit.RoundFractionalValues = 'on';
            app.GenEdit.ValueDisplayFormat = '%.0f';
            addLabel(left,14,'Display delay (s)');
            app.DelayEdit = addNum(left,14,0.05,[0 2]);

            app.GenerateBtn = uibutton(left,'push','Text','Generate Filter', ...
                'FontWeight','bold','ButtonPushedFcn',@(~,~) app.onGenerate());
            app.GenerateBtn.Layout.Row = 15; app.GenerateBtn.Layout.Column = [1 2];
            app.StopBtn = uibutton(left,'push','Text','Stop','Enable','off', ...
                'ButtonPushedFcn',@(~,~) app.onStop());
            app.StopBtn.Layout.Row = 16; app.StopBtn.Layout.Column = [1 2];

            app.GenLabel = uilabel(left,'Text','Generation: 0','FontSize',20, ...
                'FontWeight','bold','HorizontalAlignment','center');
            app.GenLabel.Layout.Row = 17; app.GenLabel.Layout.Column = [1 2];

            app.InfoArea = uitextarea(left,'Editable','off', ...
                'Value',{'Select specifications and press Generate Filter.'});
            app.InfoArea.Layout.Row = 18; app.InfoArea.Layout.Column = [1 2];

            right = uigridlayout(main,[2 2]);
            right.Layout.Row = 1; right.Layout.Column = 2;
            right.RowHeight = {'1.4x','1x'};
            right.ColumnWidth = {'1x','1.3x'};

            app.AxPZ = uiaxes(right);
            app.AxPZ.Layout.Row = 1; app.AxPZ.Layout.Column = 1;
            title(app.AxPZ,'Pole-Zero Diagram');
            xlabel(app.AxPZ,'Real'); ylabel(app.AxPZ,'Imaginary');
            grid(app.AxPZ,'on'); hold(app.AxPZ,'on');
            t = linspace(0,2*pi,361);
            plot(app.AxPZ,cos(t),sin(t),'k-');
            app.hZ = plot(app.AxPZ,NaN,NaN,'o','Color',[0 0.45 0.74], ...
                'MarkerSize',8,'LineWidth',1.5);
            app.hP = plot(app.AxPZ,NaN,NaN,'x','Color',[0.85 0.1 0.1], ...
                'MarkerSize',9,'LineWidth',1.8);
            app.AxPZ.XLim = [-1.6 1.6]; app.AxPZ.YLim = [-1.6 1.6];
            app.AxPZ.DataAspectRatio = [1 1 1];
            legend(app.AxPZ,[app.hZ app.hP],{'Zeros','Poles'},'Location','northeast');

            app.AxMag = uiaxes(right);
            app.AxMag.Layout.Row = 1; app.AxMag.Layout.Column = 2;
            title(app.AxMag,'Frequency Response');
            xlabel(app.AxMag,'Frequency (Hz)'); ylabel(app.AxMag,'Magnitude (dB)');
            grid(app.AxMag,'on'); hold(app.AxMag,'on');
            app.hMag = plot(app.AxMag,NaN,NaN,'b-','LineWidth',1.6);
            app.AxMag.YLim = [-100 5];

            app.AxCost = uiaxes(right);
            app.AxCost.Layout.Row = 2; app.AxCost.Layout.Column = [1 2];
            title(app.AxCost,'Convergence');
            xlabel(app.AxCost,'Generation'); ylabel(app.AxCost,'Best cost');
            grid(app.AxCost,'on'); hold(app.AxCost,'on');
            app.AxCost.YScale = 'log';
            app.hCost = plot(app.AxCost,NaN,NaN,'m-','LineWidth',1.5);
        end

        % --------------------------------------------------------------
        function onTypeChanged(app)
            sc = app.FsEdit.Value/8000;
            switch app.TypeDD.Value
                case 'Low Pass'
                    lab = {'Passband edge (Hz)','(not used)','Stopband edge (Hz)','(not used)'};
                    val = [1000 0 1500 0]; en = [1 0 1 0];
                case 'High Pass'
                    lab = {'Passband edge (Hz)','(not used)','Stopband edge (Hz)','(not used)'};
                    val = [1500 0 1000 0]; en = [1 0 1 0];
                case 'Band Pass'
                    lab = {'Passband low (Hz)','Passband high (Hz)','Stopband low (Hz)','Stopband high (Hz)'};
                    val = [1200 2000 800 2400]; en = [1 1 1 1];
                otherwise % Band Stop
                    lab = {'Passband low (Hz)','Passband high (Hz)','Stopband low (Hz)','Stopband high (Hz)'};
                    val = [800 2400 1200 2000]; en = [1 1 1 1];
            end
            val = val*sc;
            onoff = {'off','on'};
            app.LblFp1.Text = lab{1}; app.LblFp2.Text = lab{2};
            app.LblFs1.Text = lab{3}; app.LblFs2.Text = lab{4};
            app.Fp1Edit.Value = val(1); app.Fp2Edit.Value = val(2);
            app.Fs1Edit.Value = val(3); app.Fs2Edit.Value = val(4);
            app.Fp1Edit.Enable = onoff{en(1)+1}; app.Fp2Edit.Enable = onoff{en(2)+1};
            app.Fs1Edit.Enable = onoff{en(3)+1}; app.Fs2Edit.Enable = onoff{en(4)+1};
            app.onMethodChanged();
        end

        function onMethodChanged(app)
            if strcmp(app.MethodDD.Value,'FIR')
                app.OrderEdit.Value = 40;
            elseif any(strcmp(app.TypeDD.Value,{'Band Pass','Band Stop'}))
                app.OrderEdit.Value = 8;
            else
                app.OrderEdit.Value = 6;
            end
        end

        function onStop(app)
            app.StopFlag = true;
        end

        function finishRun(app)
            try
                if isvalid(app) && isvalid(app.UIFigure)
                    app.GenerateBtn.Enable = 'on';
                    app.StopBtn.Enable = 'off';
                end
            catch
            end
        end

        % --------------------------------------------------------------
        function ok = readSpecs(app)
            ok = false;
            S = struct();
            S.type = app.TypeDD.Value;
            S.method = app.MethodDD.Value;
            S.opt = app.OptDD.Value;
            Fs = app.FsEdit.Value; S.Fs = Fs; nyq = Fs/2;
            fp1 = app.Fp1Edit.Value; fp2 = app.Fp2Edit.Value;
            fs1 = app.Fs1Edit.Value; fs2 = app.Fs2Edit.Value;
            N = round(app.OrderEdit.Value);

            switch S.type
                case 'Low Pass'
                    good = 0<fp1 && fp1<fs1 && fs1<nyq;
                    msg = 'Require 0 < passband edge < stopband edge < Fs/2.';
                case 'High Pass'
                    good = 0<fs1 && fs1<fp1 && fp1<nyq;
                    msg = 'Require 0 < stopband edge < passband edge < Fs/2.';
                case 'Band Pass'
                    good = 0<fs1 && fs1<fp1 && fp1<fp2 && fp2<fs2 && fs2<nyq;
                    msg = 'Require 0 < stopband low < passband low < passband high < stopband high < Fs/2.';
                otherwise
                    good = 0<fp1 && fp1<fs1 && fs1<fs2 && fs2<fp2 && fp2<nyq;
                    msg = 'Require 0 < passband low < stopband low < stopband high < passband high < Fs/2.';
            end
            if ~good
                uialert(app.UIFigure,msg,'Invalid specification');
                return
            end

            S.note = '';
            twoBand = any(strcmp(S.type,{'High Pass','Band Stop'}));
            if strcmp(S.method,'FIR') && twoBand && mod(N,2)==1
                N = N+1; S.note = 'Order raised to an even value (required for symmetric FIR high-pass / band-stop).';
            end
            if strcmp(S.method,'IIR') && any(strcmp(S.type,{'Band Pass','Band Stop'})) && N<2
                N = 2; S.note = 'Order raised to 2.';
            end
            app.OrderEdit.Value = N;
            S.N = N;

            wp1 = fp1/nyq; wp2 = fp2/nyq; ws1 = fs1/nyq; ws2 = fs2/nyq;
            wg = linspace(0,1,1024).';
            switch S.type
                case 'Low Pass'
                    S.pass = wg<=wp1;               S.stop = wg>=ws1;
                    S.passEdges = fp1;              S.stopEdges = fs1;
                case 'High Pass'
                    S.pass = wg>=wp1;               S.stop = wg<=ws1;
                    S.passEdges = fp1;              S.stopEdges = fs1;
                case 'Band Pass'
                    S.pass = wg>=wp1 & wg<=wp2;     S.stop = wg<=ws1 | wg>=ws2;
                    S.passEdges = [fp1 fp2];        S.stopEdges = [fs1 fs2];
                otherwise
                    S.pass = wg<=wp1 | wg>=wp2;     S.stop = wg>=ws1 & wg<=ws2;
                    S.passEdges = [fp1 fp2];        S.stopEdges = [fs1 fs2];
            end
            if ~any(S.pass) || ~any(S.stop)
                uialert(app.UIFigure,'A band is too narrow for the frequency grid.','Invalid specification');
                return
            end
            S.wg = wg;
            S.Rp = app.RpEdit.Value; S.As = app.AsEdit.Value;
            S.dp = 1-10^(-S.Rp/20);
            S.ds = 10^(-S.As/20);
            S.P = round(app.PopEdit.Value);
            S.G = round(app.GenEdit.Value);
            S.delay = app.DelayEdit.Value;

            if strcmp(S.method,'FIR')
                S.E = exp(-1j*pi*wg*(0:N));
                S.D = floor(N/2)+1;
                S.lb = -ones(1,S.D); S.ub = ones(1,S.D);
            else
                S.z1 = exp(-1j*pi*wg);
                S.z2 = S.z1.^2;
                S.nsec = floor(N/2);
                S.hasFirst = mod(N,2)==1;
                lb = []; ub = [];
                for s = 1:S.nsec
                    lb = [lb 0 0 0 0];                 %#ok<AGROW>
                    ub = [ub 0.98 pi 1 pi];            %#ok<AGROW>
                end
                if S.hasFirst
                    lb = [lb -0.98 -1]; ub = [ub 0.98 1];
                end
                S.lb = lb; S.ub = ub; S.D = numel(lb);
            end
            app.S = S;
            ok = true;
        end

        % --------------------------------------------------------------
        function h = firCoeffs(app,p)
            N = app.S.N; p = p(:).';
            if mod(N,2)==0
                h = [p fliplr(p(1:end-1))];
            else
                h = [p fliplr(p)];
            end
            h = h(:);
        end

        function [H,g] = evalFilter(app,p)
            S = app.S; g = 1;
            if strcmp(S.method,'FIR')
                H = S.E*app.firCoeffs(p);
            else
                H = ones(numel(S.wg),1); k = 1;
                for s = 1:S.nsec
                    rp = p(k); tp = p(k+1); rz = p(k+2); tz = p(k+3); k = k+4;
                    num = 1 - 2*rz*cos(tz)*S.z1 + rz^2*S.z2;
                    den = 1 - 2*rp*cos(tp)*S.z1 + rp^2*S.z2;
                    H = H.*num./den;
                end
                if S.hasFirst
                    H = H.*(1 - p(k+1)*S.z1)./(1 - p(k)*S.z1);
                end
                A = abs(H(S.pass));
                g = 2/(max(A)+min(A));
                if ~isfinite(g) || g<=0, g = 1; end
                H = g*H;
            end
        end

        function [zs,ps] = pzOf(app,p)
            S = app.S;
            if strcmp(S.method,'FIR')
                zs = roots(app.firCoeffs(p));
                ps = 0;
            else
                zs = []; ps = []; k = 1;
                for s = 1:S.nsec
                    rp = p(k); tp = p(k+1); rz = p(k+2); tz = p(k+3); k = k+4;
                    ps = [ps; rp*exp(1j*tp); rp*exp(-1j*tp)];   %#ok<AGROW>
                    zs = [zs; rz*exp(1j*tz); rz*exp(-1j*tz)];   %#ok<AGROW>
                end
                if S.hasFirst
                    ps = [ps; p(k)]; zs = [zs; p(k+1)];
                end
            end
        end

        function a = denomPoly(app,p)
            S = app.S; a = 1; k = 1;
            for s = 1:S.nsec
                a = conv(a,[1 -2*p(k)*cos(p(k+1)) p(k)^2]);
                k = k+4;
            end
            if S.hasFirst
                a = conv(a,[1 -p(k)]);
            end
        end

        function c = objective(app,p)
            H = app.evalFilter(p);
            S = app.S; A = abs(H);
            pe = abs(A(S.pass)-1)/S.dp;
            se = A(S.stop)/S.ds;
            c = mean(pe.^2) + mean(se.^2) + max(pe) + max(se);
            if ~isfinite(c), c = 1e12; end
        end

        function [rip,att,met] = metrics(app,H)
            S = app.S; A = abs(H);
            rip = max(abs(20*log10(max(A(S.pass),1e-12))));
            att = -20*log10(max(A(S.stop))+1e-12);
            met = max(abs(A(S.pass)-1))<=S.dp && max(A(S.stop))<=S.ds;
        end

        function met = isMet(app,p)
            [~,~,met] = app.metrics(app.evalFilter(p));
        end

        % --------------------------------------------------------------
        function setupSpecLines(app)
            if ~isempty(app.SpecLines)
                delete(app.SpecLines(isgraphics(app.SpecLines)));
            end
            S = app.S; ax = app.AxMag; nyq = S.Fs/2; L = gobjects(0);
            for e = S.passEdges
                L(end+1) = plot(ax,[e e],[-120 10],'--','Color',[0 0.6 0]);   %#ok<AGROW>
            end
            for e = S.stopEdges
                L(end+1) = plot(ax,[e e],[-120 10],'--','Color',[0.85 0.1 0.1]); %#ok<AGROW>
            end
            L(end+1) = plot(ax,[0 nyq],[-S.As -S.As],':','Color',[0.85 0.1 0.1]);
            L(end+1) = plot(ax,[0 nyq],[-S.Rp -S.Rp],':','Color',[0 0.6 0]);
            app.SpecLines = L;
            ax.XLim = [0 nyq]; ax.YLim = [-100 5];
            set(app.hMag,'XData',NaN,'YData',NaN);
            set(app.hCost,'XData',NaN,'YData',NaN);
            set(app.hZ,'XData',NaN,'YData',NaN);
            set(app.hP,'XData',NaN,'YData',NaN);
        end

        function updateDisplay(app,p,gen,hist)
            S = app.S;
            [H,~] = app.evalFilter(p);
            [zs,ps] = app.pzOf(p);
            f = S.wg*S.Fs/2;
            set(app.hMag,'XData',f,'YData',20*log10(max(abs(H),1e-6)));
            set(app.hZ,'XData',real(zs),'YData',imag(zs));
            set(app.hP,'XData',real(ps),'YData',imag(ps));
            set(app.hCost,'XData',0:gen,'YData',max(hist(1:gen+1),1e-12));
            title(app.AxPZ,sprintf('Pole-Zero Diagram  |  Generation %d',gen));
            title(app.AxMag,sprintf('Frequency Response  |  Generation %d',gen));
            app.GenLabel.Text = sprintf('Generation: %d / %d',gen,S.G);
            [rip,att,met] = app.metrics(H);
            yn = {'No','Yes'};
            app.InfoArea.Value = { ...
                sprintf('%s %s, order %d (%s)',S.type,S.method,S.N,S.opt), ...
                sprintf('Best cost: %.4g',hist(gen+1)), ...
                sprintf('Passband max dev: %.3f dB (limit %.2f)',rip,S.Rp), ...
                sprintf('Stopband atten: %.2f dB (target %.1f)',att,S.As), ...
                sprintf('Specification met: %s',yn{met+1})};
            drawnow limitrate
        end

        function finalReport(app,p,gen,hist,stopped)
            S = app.S;
            [H,g] = app.evalFilter(p);
            [rip,att,met] = app.metrics(H);
            if met
                st = 'Design converged: specification met.';
            elseif stopped
                st = 'Stopped by user.';
            else
                st = 'Max generations reached: specification NOT met.';
            end
            lines = {st, ...
                sprintf('%s %s, order %d, %s',S.type,S.method,S.N,S.opt), ...
                sprintf('Generations used: %d',gen), ...
                sprintf('Final cost: %.4g',hist(gen+1)), ...
                sprintf('Passband max dev: %.3f dB',rip), ...
                sprintf('Stopband atten: %.2f dB',att)};
            if strcmp(S.method,'IIR')
                rmax = max(abs(roots(app.denomPoly(p))));
                if rmax<1, sv = 'STABLE'; else, sv = 'UNSTABLE'; end
                lines{end+1} = sprintf('Max |pole| = %.4f -> %s',rmax,sv);
                lines{end+1} = sprintf('Gain factor = %.4g',g);
            else
                lines{end+1} = 'FIR: all poles at z = 0 -> always stable';
                lines{end+1} = sprintf('Taps: %d (symmetric, linear phase)',S.N+1);
            end
            if ~isempty(S.note), lines{end+1} = S.note; end
            app.InfoArea.Value = lines;
        end

        % --------------------------------------------------------------
        function onGenerate(app)
            if ~app.readSpecs(), return; end
            S = app.S;
            app.StopFlag = false;
            app.GenerateBtn.Enable = 'off';
            app.StopBtn.Enable = 'on';
            cleaner = onCleanup(@() app.finishRun()); %#ok<NASGU>
            app.setupSpecLines();

            P = S.P; D = S.D; lb = S.lb; ub = S.ub; rng('shuffle');
            range = ub-lb;
            if strcmp(S.method,'FIR')
                X = (rand(P,D)-0.5)*0.4;
            else
                X = lb + range.*rand(P,D);
            end
            F = zeros(P,1);
            for i = 1:P, F(i) = app.objective(X(i,:)); end
            usePSO = strcmp(S.opt,'PSO');
            if usePSO
                V = (rand(P,D)-0.5).*range*0.1;
                PB = X; PF = F;
            end
            [bf,ib] = min(F); best = X(ib,:);
            hist = nan(S.G+1,1); hist(1) = bf;
            app.updateDisplay(best,0,hist);
            gen = 0; met = app.isMet(best);

            while gen<S.G && ~app.StopFlag && ~met
                if ~isvalid(app) || ~isvalid(app.UIFigure), return; end
                gen = gen+1;
                if usePSO
                    w = 0.9 - 0.5*(gen/S.G);
                    V = w*V + 1.6*rand(P,D).*(PB-X) + 1.6*rand(P,D).*(best-X);
                    vmax = 0.25*range;
                    V = max(min(V,vmax),-vmax);
                    X = X+V;
                    out = X<lb | X>ub;
                    V(out) = -0.5*V(out);
                    X = min(max(X,lb),ub);
                    for i = 1:P, F(i) = app.objective(X(i,:)); end
                    imp = F<PF;
                    PB(imp,:) = X(imp,:); PF(imp) = F(imp);
                    [bf,ib] = min(PF); best = PB(ib,:);
                else
                    [F,ix] = sort(F); X = X(ix,:);
                    nE = 2; Xn = X; pm = 0.2;
                    sig = range*(0.15*(1-gen/S.G)+0.005);
                    k = nE+1;
                    while k<=P
                        p1 = X(min(randi(P,1,3)),:);
                        p2 = X(min(randi(P,1,3)),:);
                        a = -0.25 + 1.5*rand(1,D);
                        c1 = a.*p1 + (1-a).*p2;
                        c2 = (1-a).*p1 + a.*p2;
                        c1 = c1 + (rand(1,D)<pm).*randn(1,D).*sig;
                        c2 = c2 + (rand(1,D)<pm).*randn(1,D).*sig;
                        Xn(k,:) = min(max(c1,lb),ub);
                        if k+1<=P
                            Xn(k+1,:) = min(max(c2,lb),ub);
                        end
                        k = k+2;
                    end
                    X = Xn;
                    for i = nE+1:P, F(i) = app.objective(X(i,:)); end
                    [bf,ib] = min(F); best = X(ib,:);
                end
                hist(gen+1) = bf;
                app.updateDisplay(best,gen,hist);
                met = app.isMet(best);
                if S.delay>0, pause(S.delay); end
            end
            app.updateDisplay(best,gen,hist);
            app.finalReport(best,gen,hist,app.StopFlag);
        end
    end
end

% ----------------------------------------------------------------------
function lb = addLabel(parent,row,txt)
    lb = uilabel(parent,'Text',txt);
    lb.Layout.Row = row; lb.Layout.Column = 1;
end

function ef = addNum(parent,row,val,lim)
    ef = uieditfield(parent,'numeric','Value',val,'Limits',lim);
    ef.Layout.Row = row; ef.Layout.Column = 2;
end
