% Same script as leader_follower_with_plotting.m but with additional data saving. Two
% data sets will be saved, one saving the distance between connected robots
% through time, and another with the distance between the leader and goal
% location when the goal is "reached".

% Sean Wilson
% 07/2019

%% Experiment Constants

%Run the simulation for a specific number of iterations
iterations = 5000;

%% Set up the Robotarium object

N = 5;
initial_positions = generate_initial_conditions(N, 'Width', 1, 'Height', 1, 'Spacing', 0.3);
r = Robotarium('NumberOfRobots', N, 'ShowFigure', true, 'InitialConditions', initial_positions);

%% Create the desired Laplacian
% Graph laplacian
% followers = -completeGL(N-1);
% L = zeros(N, N);
% L(2:N, 2:N) = followers;
% L(2, 2) = L(2, 2) + 1;

A = [0 1 0 0 0;
     1 0 1 0 1;
     0 1 0 1 0;
     0 0 1 0 1;
     0 1 0 1 0];
D = [1 0 0 0 0;
     0 3 0 0 0;
     0 0 2 0 0;
     0 0 0 2 0;
     0 0 0 0 2];
L = D - A;
followers = -L(2:N, 2:N);
L(2, 1) = -1;


%Initialize velocity vector
dxi = zeros(2, N);

%State for leader
state = 1;

% These are gains for our formation control algorithm
formation_control_gain = 10;
desired_distance = 0.2;

%% Grab tools we need to convert from single-integrator to unicycle dynamics

% Single-integrator -> unicycle dynamics mapping
si_to_uni_dyn = create_si_to_uni_dynamics('LinearVelocityGain', 0.8);
% Single-integrator barrier certificates
uni_barrier_cert = create_uni_barrier_certificate_with_boundary();
% Single-integrator position controller
leader_controller = create_automatic_parking_controller('ApproachAngleGain', 1.2, 'DesiredAngleGain', 3);

waypoints = [-0.8 0.6 -pi/2; -0.8 -0.6 0; 0.8 -0.6 pi/2; 0.8 0.6 pi]';
close_enough = 0.03;

%% Plotting Setup

% Color Vector for Plotting
% Note the Robotarium MATLAB instance runs in a docker container which will 
% produce the same rng value every time unless seeded by the user.
CM = ['k','b','r','g'];

%Marker, font, and line sizes
marker_size_goal = determine_marker_size(r, 0.20);
font_size = determine_font_size(r, 0.05);
line_width = 5;

% Create goal text and markers.
for i = 1:length(waypoints)
    % Text with goal identification
    goal_caption = sprintf('G%d', i);
    % Plot colored square for goal location.
    g(i) = plot(waypoints(1,i), waypoints(2,i),'s','MarkerSize',marker_size_goal,'LineWidth',line_width,'Color',CM(i));
    % Plot the goal identification text inside the goal location
    goal_labels{i} = text(waypoints(1,i)-0.05, waypoints(2,i), goal_caption, 'FontSize', font_size, 'FontWeight', 'bold');
    % Plot arrow to indicate goal orientation
    quiver(waypoints(1,i), waypoints(2,i), 0.1*cos(waypoints(3,i)), 0.1*sin(waypoints(3,i)), 'Color', CM(i), 'LineWidth', line_width);
end

% Plot graph connections
%Need location of robots
x=r.get_poses();

% Follower connections to each other
[rows, cols] = find(A == 1);

% Only considering half due to symmetric nature
for k = 1:length(rows)
    if rows(k) > cols(k)-1 % Éviter de tracer les doublons
        lf(k) = line([x(1,rows(k)), x(1,cols(k))], ...
                     [x(2,rows(k)), x(2,cols(k))], ...
                     'LineWidth', line_width, 'Color', 'b');
    end
end


% Leader connection assuming only connection between first and second
% robot.
ll = line([x(1,1), x(1,2)],[x(2,1), x(2,2)], 'LineWidth', line_width, 'Color', 'r'); 

% Follower plot setup
for j = 1:N-1    
    % Text for robot identification
    follower_caption{j} = sprintf('Follower Robot %d', j);
    % Plot the robot label text 
    follower_labels{j} = text(500, 500, follower_caption{j}, 'FontSize', font_size, 'FontWeight', 'bold');
end

%Leader plot setup
leader_label = text(500, 500, 'Leader Robot', 'FontSize', font_size, 'FontWeight', 'bold', 'Color', 'r');

%% Data Saving Setup

%Preallocate what we can.
robot_distance = zeros(5,iterations); % 4 distances and time
goal_distance = []; % Cannot preallocate this as we do not know how many
                   % times the goal will be reached.
start_time = tic;

r.step();

for t = 1:iterations
    
    % Retrieve the most recent poses from the Robotarium.  The time delay is
    % approximately 0.033 seconds
    x = r.get_poses();
    
    %% Algorithm
    
    for i = 2:N
        
        %Zero velocity and get the topological neighbors of agent i
        dxi(:, i) = [0 ; 0];
        
        neighbors = topological_neighbors(L, i);
        
        for j = neighbors
            dxi(:, i) = dxi(:, i) + ...
                formation_control_gain*(norm(x(1:2, j) - x(1:2, i))^2 -  desired_distance^2)*(x(1:2, j) - x(1:2, i));
        end
    end
    
    %% Make the leader travel between waypoints
    
    waypoint = waypoints(:, state);
    
    switch state        
        case 1
            dxi(:, 1) = leader_controller(x(1:3, 1), waypoint);
            if(norm(x(1:2, 1) - waypoint(1:2)) < close_enough)
                state = 2;
            end
        case 2
            dxi(:, 1) = leader_controller(x(1:3, 1), waypoint);
            if(norm(x(1:2, 1) - waypoint(1:2)) < close_enough)
                state = 3;
            end
        case 3
            dxi(:, 1) = leader_controller(x(1:3, 1), waypoint);
            if(norm(x(1:2, 1) - waypoint(1:2)) < close_enough)
                state = 4;
            end
        case 4
            dxi(:, 1) = leader_controller(x(1:3, 1), waypoint);
            if(norm(x(1:2, 1) - waypoint(1:2)) < close_enough)
                state = 1;
            end
    end
    
        
    %% Avoid actuator errors
    
    % To avoid errors, we need to threshold dxi
    norms = arrayfun(@(x) norm(dxi(:, x)), 1:N);
    threshold = 3/4*r.max_linear_velocity;
    to_thresh = norms > threshold;
    dxi(:, to_thresh) = threshold*dxi(:, to_thresh)./norms(to_thresh);
    
    %% Use barrier certificate and convert to unicycle dynamics
    % dxu = si_to_uni_dyn(dxi, x);
    dxu = dxi;
    dxu(:, 2:end) = si_to_uni_dyn(dxi(:, 2:end), x(:, 2:end));
    dxu = uni_barrier_cert(dxu, x);
    
    %% Send velocities to agents
    
    %Set velocities
    r.set_velocities(1:N, dxu);
    
    %% Update Plot Handles
    
    %Update position of labels for followers
    for q = 1:N-1
        follower_labels{q}.Position = x(1:2, q+1) + [-0.15;0.15];    
    end
    
    %Update position of graph connection lines
    for m = 1:size(lf, 2)
        % If not a graphics
        if ~isgraphics(lf(m))
            continue;
        end
        lf(m).XData = [x(1,rows(m)), x(1,cols(m))];
        lf(m).YData = [x(2,rows(m)), x(2,cols(m))];
    end
    
    %Update position of label and graph connection for leader
    leader_label.Position = x(1:2, 1) + [-0.15;0.15];
    ll.XData = [x(1,1), x(1,2)];
    ll.YData = [x(2,1), x(2,2)];
    
    % Resize Marker Sizes (In case user changes simulated figure window
    % size, this is unnecessary in submission as the figure window 
    % does not change size).

    marker_size_goal = num2cell(ones(1,length(waypoints))*determine_marker_size(r, 0.20));
    [g.MarkerSize] = marker_size_goal{:};
    font_size = determine_font_size(r, 0.05);
    leader_label.FontSize = font_size;
    
    for n = 1:N
        % Have to update font in loop for some conversion reasons.
        % Again this is unnecessary when submitting as the figure
        % window does not change size when deployed on the Robotarium.
        follower_labels{n}.FontSize = font_size;
        goal_labels{n}.FontSize = font_size;
    end
    
    %% Compute data to be saved and store in matrix.
    % Distances between connected robots.
    robot_distance(1,t) = norm([x(1:2,1) - x(1:2,2)],2);
    robot_distance(5,t) = toc(start_time);
    for b = 1:length(rows)/2+1
        robot_distance(b+1,t) = norm([x(1:2,rows(b)) - x(1:2,cols(b))],2);   
    end
    
    if(norm(x(1:2, 1) - waypoint(1:2)) < close_enough)
        goal_distance = [goal_distance [norm(x(1:2, 1) - waypoint(1:2));toc(start_time)]];
    end
    
    %Iterate experiment
    r.step();
end

% Save the data
save('DistanceData.mat', 'robot_distance');
save('GoalData.mat', 'goal_distance');

% We can call this function to debug our experiment!  Fix all the errors
% before submitting to maximize the chance that your experiment runs
% successfully.
r.debug();

%% Helper Functions

% Marker Size Helper Function to scale size with figure window
% Input: robotarium instance, desired size of the marker in meters
function marker_size = determine_marker_size(robotarium_instance, marker_size_meters)

% Get the size of the robotarium figure window in pixels
curunits = get(robotarium_instance.figure_handle, 'Units');
set(robotarium_instance.figure_handle, 'Units', 'Points');
cursize = get(robotarium_instance.figure_handle, 'Position');
set(robotarium_instance.figure_handle, 'Units', curunits);

% Determine the ratio of the robot size to the x-axis (the axis are
% normalized so you could do this with y and figure height as well).
marker_ratio = (marker_size_meters)/(robotarium_instance.boundaries(2) -...
    robotarium_instance.boundaries(1));

% Determine the marker size in points so it fits the window. cursize(3) is
% the width of the figure window in pixels. (the axis are
% normalized so you could do this with y and figure height as well).
marker_size = cursize(3) * marker_ratio;

end

% Font Size Helper Function to scale size with figure window
% Input: robotarium instance, desired height of the font in meters
function font_size = determine_font_size(robotarium_instance, font_height_meters)

% Get the size of the robotarium figure window in point units
curunits = get(robotarium_instance.figure_handle, 'Units');
set(robotarium_instance.figure_handle, 'Units', 'Points');
cursize = get(robotarium_instance.figure_handle, 'Position');
set(robotarium_instance.figure_handle, 'Units', curunits);

% Determine the ratio of the font height to the y-axis
font_ratio = (font_height_meters)/(robotarium_instance.boundaries(4) -...
    robotarium_instance.boundaries(3));

% Determine the font size in points so it fits the window. cursize(4) is
% the hight of the figure window in points.
font_size = cursize(4) * font_ratio;

end
