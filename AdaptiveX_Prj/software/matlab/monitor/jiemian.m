function varargout = jiemian(varargin)
% JIEMIAN Open the fixed-layout monitor for the current Rx RX264 UDP stream.
% jiemian; Click Start to receive; P/M/FID are decoded from each Rx packet.
% h = jiemian returns the figure; [h,app] = jiemian also returns the monitor.
% jiemian('Visible','off') supports automated checks.
    persistent monitor
    if isempty(monitor) || ~isvalid(monitor) || ~isgraphics(monitor.Figure)
        monitor = LinkQualityMonitor(varargin{:});
        try
            JiemianUDPReceiver(monitor);
        catch exception
            delete(monitor);
            monitor = [];
            rethrow(exception)
        end
    elseif isempty(varargin)
        monitor.Figure.Visible = 'on';
    else
        set(monitor.Figure,varargin{:});
    end
    if nargout >= 1, varargout{1} = monitor.Figure; end
    if nargout >= 2, varargout{2} = monitor; end
end
