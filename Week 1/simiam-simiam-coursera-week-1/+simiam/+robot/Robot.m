classdef Robot < simiam.ui.Drawable

% Copyright (C) 2013, Georgia Tech Research Corporation
% see the LICENSE file included with this software
    
    properties
        supervisor
        
        driver
        optitrack
        hostname
        port
        islinked
    end
    
    methods
        function obj = Robot(parent, start_pose)
            obj = obj@simiam.ui.Drawable(parent, start_pose);
            obj.islinked = false;
            obj.driver = [];
            obj.optitrack = [];
        end
        
        function attach_supervisor(obj, supervisor)
            obj.supervisor = supervisor;
            supervisor.attach_robot(obj);
        end
    end
    
end

