classdef QBSupervisor < simiam.controller.Supervisor
%% SUPERVISOR switches between controllers and handles their inputs/outputs.
%
% Properties:
%   current_controller      - Currently selected controller
%   controllers             - List of available controllers
%   goal_points             - Set of goal points
%   goal_index              - Pointer to current goal point
%   v                       - Robot velocity
%
% Methods:
%   execute - Selects and executes the current controller.

% Copyright (C) 2013, Georgia Tech Research Corporation
% see the LICENSE file included with this software

    properties
    %% PROPERTIES
    
        states
        eventsd
        
        current_state

        prev_ticks          % Previous tick count on the left and right wheels
        
        v
        theta_d
        goal
        
        d_stop
        d_at_obs
        d_unsafe
        d_fw
        d_prog
        
        p
        
        v_max_w0            % QuickBot's max linear velocity when w=0
        w_max_v0            % QuickBot's max angular velocity when v=0
        v_min_w0
        w_min_v0
        
        switch_count
        
        fw_direction
    end
    
    methods
    %% METHODS
        
        function obj = QBSupervisor()
        %% SUPERVISOR Constructor
            obj = obj@simiam.controller.Supervisor();
            
            % initialize the controllers
            obj.controllers{1} = simiam.controller.Stop();
            obj.controllers{2} = simiam.controller.GoToAngle();
            obj.controllers{3} = simiam.controller.GoToGoal();
            obj.controllers{4} = simiam.controller.AvoidObstacles();
            obj.controllers{5} = simiam.controller.AOandGTG();
            obj.controllers{6} = simiam.controller.FollowWall();
            obj.controllers{7} = simiam.controller.SlidingMode();
            
            % set the initial controller
            obj.current_controller = obj.controllers{3};
            obj.current_state = 3;
            
            % generate the set of states
            for i = 1:length(obj.controllers)
                obj.states{i} = struct('state', obj.controllers{i}.type, ...
                                       'controller', obj.controllers{i});
            end
            
            % define the set of eventsd
            obj.eventsd{1} = struct('event', 'at_obstacle', ...
                                   'callback', @at_obstacle);
            
            obj.eventsd{2} = struct('event', 'at_goal', ...
                                   'callback', @at_goal);
            
            obj.eventsd{3} = struct('event', 'obstacle_cleared', ...
                                    'callback', @obstacle_cleared);
                                
            obj.eventsd{4} = struct('event', 'unsafe', ...
                                    'callback', @unsafe);
                                
            obj.eventsd{5} = struct('event', 'progress_made', ...
                                    'callback', @progress_made);
                                
            obj.eventsd{6} = struct('event', 'sliding_left', ...
                                    'callback', @sliding_left);
                               
            obj.eventsd{7} = struct('event', 'sliding_right', ...
                                    'callback', @sliding_right);
                               
            obj.prev_ticks = struct('left', 0, 'right', 0);
            
            obj.theta_d     = pi/4;
            
            %% START CODE BLOCK %%
            obj.v           = 0.15;
            obj.goal        = [1.1, 1.1];
            obj.d_stop      = 0.05;
            obj.d_at_obs    = 0.10;                
            obj.d_unsafe    = 0.05;
            obj.d_fw        = 0.17;
            obj.fw_direction   = 'left';
            %% END CODE BLOCK %%
                                    
            obj.p = simiam.util.Plotter();
            obj.current_controller.p = obj.p;
            
            obj.d_prog = 10;
            
            obj.switch_count = 0;
        end
        
        function execute(obj, dt)
        %% EXECUTE Selects and executes the current controller.
        %   execute(obj, robot) will select a controller from the list of
        %   available controllers and execute it.
        %
        %   See also controller/execute
        
            obj.update_odometry();
        
            inputs = obj.controllers{7}.inputs; 
            inputs.v = obj.v;
            inputs.d_fw = obj.d_fw;
            inputs.x_g = obj.goal(1);
            inputs.y_g = obj.goal(2);
            
            %% START CODE BLOCK %%
            
            ir_distances = obj.robot.get_ir_distances();

            if (obj.check_event('at_goal'))
                if (~obj.is_in_state('stop'))
                    [x,y,theta] = obj.state_estimate.unpack();
                    fprintf('stopped at (%0.3f,%0.3f)\n', x, y);
                end
                obj.switch_to_state('stop');

            elseif (obj.check_event('at_obstacle'))
                if sliding_left(obj)
                    inputs.direction='left';
                    set_progress_point(obj);
                    obj.switch_to_state('follow_wall');
                elseif sliding_right(obj)
                    inputs.direction='right';
                    set_progress_point(obj);
                    obj.switch_to_state('follow_wall');
                end
            elseif (obj.is_in_state('follow_wall')) && progress_made(obj)
                obj.switch_to_state('ao_and_gtg')
            elseif ~(obj.is_in_state('follow_wall')) && (obj.is_in_state('unsafe'))
                obj.switch_to_state('avoid_obstacle')
                   
            end
            
            %% END CODE BLOCK %%
            
            inputs.direction = obj.fw_direction;
            outputs = obj.current_controller.execute(obj.robot, obj.state_estimate, inputs, dt);
                
            [vel_r, vel_l] = obj.ensure_w(obj.robot, outputs.v, outputs.w);
            obj.robot.set_wheel_speeds(vel_r, vel_l);

%             [x, y, theta] = obj.state_estimate.unpack();
%             fprintf('current_pose: (%0.3f,%0.3f,%0.3f)\n', x, y, theta);
        end
        
        function set_progress_point(obj)
            [x, y, theta] = obj.state_estimate.unpack();
            obj.d_prog = min(norm([x-obj.goal(1);y-obj.goal(2)]), obj.d_prog);
        end
        
        %% Events %%
        
        function rc = sliding_left(obj, state, robot)
            inputs = obj.controllers{7}.inputs;
            inputs.x_g = obj.goal(1);
            inputs.y_g = obj.goal(2);
            inputs.direction = 'left';
            
            obj.controllers{7}.execute(obj.robot, obj.state_estimate, inputs, 0);
            
            u_gtg = obj.controllers{7}.u_gtg;
            u_ao = obj.controllers{7}.u_ao;
            u_fw = obj.controllers{7}.u_fw;
                        
            %% START CODE BLOCK %%
            vector_gtg_ao=[u_gtg,u_ao];
            sigma =vector_gtg_ao\u_fw;
            %% END CODE BLOCK %%

            rc = false;
            if sigma(1) > 0 && sigma(2) > 0
%                 fprintf('now sliding left\n');
                rc = true;
            end
        end
        
        function rc = sliding_right(obj, state, robot)
            inputs = obj.controllers{7}.inputs;
            inputs.x_g = obj.goal(1);
            inputs.y_g = obj.goal(2);
            inputs.direction = 'right';
            
            obj.controllers{7}.execute(obj.robot, obj.state_estimate, inputs, 0);
            
            u_gtg = obj.controllers{7}.u_gtg;
            u_ao = obj.controllers{7}.u_ao;
            u_fw = obj.controllers{7}.u_fw;
            
            %% START CODE BLOCK
            vector_gtg_ao=[u_gtg,u_ao];
            sigma =vector_gtg_ao\u_fw;
            %% END CODE BLOCK
            
            rc = false;
            if sigma(1) > 0 && sigma(2) > 0
%                 fprintf('now sliding right\n');
                rc = true;
            end
        end
        
        function rc = progress_made(obj, state, robot)

            % Check for any progress
            [x, y, theta] = obj.state_estimate.unpack();            
            rc = false;
            
            %% START CODE BLOCK %%
            status=[x-obj.goal(1);y-obj.goal(2)];
            epsilon=0.1;
            
            if norm(status)<(obj.d_prog-epsilon)
                rc = true;
            end
            
            %% END CODE BLOCK %%
            
        end

        function rc = at_goal(obj, state, robot)
            [x,y,theta] = obj.state_estimate.unpack();
            rc = false;
            
            % Test distance from goal
            if norm([x - obj.goal(1); y - obj.goal(2)]) < obj.d_stop
                rc = true;
            end
        end
        
        function rc = at_obstacle(obj, state, robot)
            ir_distances = obj.robot.get_ir_distances();
            rc = false;                                     % Assume initially that the robot is clear of obstacle
            
            % Loop through and test the sensors (only the front set)
            if any(ir_distances(1:5) < obj.d_at_obs)
                rc = true;
            end
        end
        
        function rc = unsafe(obj, state, robot)
            ir_distances = obj.robot.get_ir_distances();              
            rc = false;             % Assume initially that the robot is clear of obstacle
            
            % Loop through and test the sensors (only the front set)
            if any(ir_distances(1:5) < obj.d_unsafe)
                    rc = true;
            end
        end
        
        function rc = obstacle_cleared(obj, state, robot)
            ir_distances = obj.robot.get_ir_distances();
            rc = false;              % Assume initially that the robot is clear of obstacle
            
            % Loop through and test the sensors (only front set)
            if all(ir_distances(1:5) > obj.d_at_obs)
                rc = true;
            end
        end
        
        
        
        %% Output shaping
        
        function [vel_r, vel_l] = ensure_w(obj, robot, v, w)
            
            % This function ensures that w is respected as best as possible
            % by scaling v.
            
            R = robot.wheel_radius;
            L = robot.wheel_base_length;
            
            vel_max = robot.max_vel;
            vel_min = robot.min_vel;
            
%             fprintf('IN (v,w) = (%0.3f,%0.3f)\n', v, w);
            
            if (abs(v) > 0)
                % 1. Limit v,w to be possible in the range [vel_min, vel_max]
                % (avoid stalling or exceeding motor limits)
                v_lim = max(min(abs(v), (R/2)*(2*vel_max)), (R/2)*(2*vel_min));
                w_lim = max(min(abs(w), (R/L)*(vel_max-vel_min)), 0);
                
                % 2. Compute the desired curvature of the robot's motion
                
                [vel_r_d, vel_l_d] = robot.dynamics.uni_to_diff(v_lim, w_lim);
                
                % 3. Find the max and min vel_r/vel_l
                vel_rl_max = max(vel_r_d, vel_l_d);
                vel_rl_min = min(vel_r_d, vel_l_d);
                
                % 4. Shift vel_r and vel_l if they exceed max/min vel
                if (vel_rl_max > vel_max)
                    vel_r = vel_r_d - (vel_rl_max-vel_max);
                    vel_l = vel_l_d - (vel_rl_max-vel_max);
                elseif (vel_rl_min < vel_min)
                    vel_r = vel_r_d + (vel_min-vel_rl_min);
                    vel_l = vel_l_d + (vel_min-vel_rl_min);
                else
                    vel_r = vel_r_d;
                    vel_l = vel_l_d;
                end
                
                % 5. Fix signs (Always either both positive or negative)
                [v_shift, w_shift] = robot.dynamics.diff_to_uni(vel_r, vel_l);
                
                v = sign(v)*v_shift;
                w = sign(w)*w_shift;
                
            else
                % Robot is stationary, so we can either not rotate, or
                % rotate with some minimum/maximum angular velocity
                w_min = R/L*(2*vel_min);
                w_max = R/L*(2*vel_max);
                
                if abs(w) > w_min
                    w = sign(w)*max(min(abs(w), w_max), w_min);
                else
                    w = 0;
                end
                
                
            end
            
%             fprintf('OUT (v,w) = (%0.3f,%0.3f)\n', v, w);
            [vel_r, vel_l] = robot.dynamics.uni_to_diff(v, w);
        end
        
        
        %% State machine support functions
        
        function set_current_controller(obj, ctrl)
            % save plots
            obj.current_controller = ctrl;
            obj.p.switch_2d_ref();
            obj.current_controller.p = obj.p;
        end
        
        function rc = is_in_state(obj, name)
            rc = strcmp(name, obj.states{obj.current_state}.state);
        end
        
        function switch_to_state(obj, name)
            
            if(~obj.is_in_state(name))
                for i=1:numel(obj.states)
                    if(strcmp(obj.states{i}.state, name))
                        obj.set_current_controller(obj.states{i}.controller);
                        obj.current_state = i;
                        fprintf('switching to state %s\n', name);
                        obj.states{i}.controller.reset();
                        obj.switch_count = obj.switch_count + 1;
                        return;
                    end
                end
            else
%                 fprintf('already in state %s\n', name);
                return
            end
            
            fprintf('no state exists with name %s\n', name);
        end
        
        function rc = check_event(obj, name)
           for i=1:numel(obj.eventsd)
               if(strcmp(obj.eventsd{i}.event, name))
                   rc = obj.eventsd{i}.callback(obj, obj.states{obj.current_state}, obj.robot);
                   return;
               end
           end
           
           % return code (rc)
           fprintf('no event exists with name %s\n', name);
           rc = false;
        end
        
        %% Odometry
        
        function update_odometry(obj)
        %% UPDATE_ODOMETRY Approximates the location of the robot.
        %   obj = obj.update_odometry(robot) should be called from the
        %   execute function every iteration. The location of the robot is
        %   updated based on the difference to the previous wheel encoder
        %   ticks. This is only an approximation.
        %
        %   state_estimate is updated with the new location and the
        %   measured wheel encoder tick counts are stored in prev_ticks.
        
            % Get wheel encoder ticks from the robot
            right_ticks = obj.robot.encoders(1).ticks;
            left_ticks = obj.robot.encoders(2).ticks;
            
            % Recal the previous wheel encoder ticks
            prev_right_ticks = obj.prev_ticks.right;
            prev_left_ticks = obj.prev_ticks.left;
            
            % Previous estimate 
            [x, y, theta] = obj.state_estimate.unpack();
            
            % Compute odometry here
            R = obj.robot.wheel_radius;
            L = obj.robot.wheel_base_length;
            m_per_tick = (2*pi*R)/obj.robot.encoders(1).ticks_per_rev;
                        
            d_right = (right_ticks-prev_right_ticks)*m_per_tick;
            d_left = (left_ticks-prev_left_ticks)*m_per_tick;
            
            d_center = (d_right + d_left)/2;
            phi = (d_right - d_left)/L;
            
            x_dt = d_center*cos(theta);
            y_dt = d_center*sin(theta);
            theta_dt = phi;
                        
            theta_new = theta + theta_dt;
            x_new = x + x_dt;
            y_new = y + y_dt;                           
%             fprintf('Estimated pose (x,y,theta): (%0.3g,%0.3g,%0.3g)\n', x_new, y_new, theta_new);
            
            % Save the wheel encoder ticks for the next estimate
            obj.prev_ticks.right = right_ticks;
            obj.prev_ticks.left = left_ticks;
            
            % Update your estimate of (x,y,theta)
            obj.state_estimate.set_pose([x_new, y_new, atan2(sin(theta_new), cos(theta_new))]);
        end
        
        %% Utility functions
        
        function attach_robot(obj, robot, pose)
            obj.robot = robot;
            [x, y, theta] = pose.unpack();
            obj.state_estimate.set_pose([x, y, theta]);

            [v_0, obj.w_max_v0] = robot.dynamics.diff_to_uni(obj.robot.max_vel, -obj.robot.max_vel);
            [obj.v_max_w0, w_0] = robot.dynamics.diff_to_uni(obj.robot.max_vel, obj.robot.max_vel);
            
            [v_0, obj.w_min_v0] = robot.dynamics.diff_to_uni(obj.robot.min_vel, -obj.robot.min_vel);
            [obj.v_min_w0, w_0] = robot.dynamics.diff_to_uni(obj.robot.min_vel, obj.robot.min_vel);
        end
    end
end
