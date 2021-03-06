function [Clusters,Axes,remainPc] = axedetect(datapc,beamWidth)
% AXEDETECT
%
% Function to detect the main axes in a planar point cloud and segment it
% automatically according to the detected axes. The algorithm employs
% Principal Componen Analysis (PCA) to transform the 3D point cloud into a
% 2D binary image, and then uses 2D Hough Transform to detect the edges and
% thereafter determines the axes.
%
% Inputs: 
% - datapc: input point cloud. The point cloud should be (more or less)
% planar
% - beamWidth: approximate width of the point cloud
%
% Outputs:
% - Clusters: a struct containing the segmented point clouds (segmented
% according the detected axes)
% - Axes: a struct containing the attributes of the axes (in 2D)
% - remainPc : the remaining unsegmented point cloud
%
% (c) Arnadi Murtiyoso (INSA Strasbourg - ICube-TRIO UMR 7357)

% tic
%% step 1: transform the point cloud into a planar XY coordinate system
% compute the Principal Component Analysis
coeffs = pca(datapc.Location);

% transform the point cloud to PC-aligned system
TransformPCA = datapc.Location*coeffs(:,1:3);

% figure('name','Transformed Point Cloud')
% pcshow(pcTransformPCA)

% project the point cloud to a plane (Z=0)
TransformPCA(:,3)=0;
pcTransformPCA = pointCloud(TransformPCA);

% determine the point cloud boundaries
minX=min(TransformPCA(:,1));
maxX=max(TransformPCA(:,1));
minY=min(TransformPCA(:,2));
maxY=max(TransformPCA(:,2));

% raster dimensions in project unit
width_m=max(TransformPCA(:,1))-min(TransformPCA(:,1));
height_m=max(TransformPCA(:,2))-min(TransformPCA(:,2));

% resolution of the raster in project unit; modifiable
resolution_pix=0.01; %this is for standard
%resolution_pix=0.005; %this is for 1cm subsampled data

% raster dimensions in pixel
width_pix=ceil(width_m/resolution_pix);
height_pix=ceil(height_m/resolution_pix);

%% step 2: create the binary image of the projected point cloud
% initialise the empty raster
raster=zeros(height_pix,width_pix);

% optional: create a waitbar
f = waitbar(0,'Converting to BW image...','Name','axedetect.m');
k=1;

% fill the pixels
for i=1:height_pix
    for j=1:width_pix
        % find the points located inside the pixel
        I=find(TransformPCA(:,1)>minX & TransformPCA(:,1)< ...
            minX+resolution_pix & TransformPCA(:,2)>minY & ...
            TransformPCA(:,2)<minY+resolution_pix);
        % if the pixel contains no points, give a black color
        if isempty(I) 
            raster(i,j)=0;
        % if the pixel contains points, give a white color
        else
            raster(i,j)=1;
        end
        % continuing on for the rows...
        minX=minX+resolution_pix;
        waitbar(k/(width_pix*height_pix),f)
        k=k+1;
    end
    % continuing on for the columns...
    minY=minY+resolution_pix;
    minX=min(TransformPCA(:,1));
end

% flip the resulting raster (needed because of the raster coord system)
raster=flip(raster);

% close the waitbar
close(f)

figure('name','Transformed Raster')
imshow(raster)
%% step 3: perform Hough Transform to detect lines
% detect edges in the raster
BW = edge(raster,'canny');

% Compute the Hough transform of the binary image returned by edge
[H,theta,rho] = hough(BW);

% % Optional: Display the transform, H, returned by the hough function.
% figure
% imshow(imadjust(rescale(H)),[],...
%        'XData',theta,...
%        'YData',rho,...
%        'InitialMagnification','fit');
% xlabel('\theta (degrees)')
% ylabel('\rho')
% axis on
% axis normal 
% hold on
% colormap(gca,hot)

% Find the peaks in the Hough transform matrix, H, using the houghpeaks 
% function.
%P = houghpeaks(H,10,'threshold',ceil(0.3*max(H(:))));
P = houghpeaks(H,15,'threshold',ceil(0.3*max(H(:))));

% Find lines in the image using the houghlines function.
%lines = houghlines(BW,theta,rho,P,'FillGap',5,'MinLength',7);
lines = houghlines(BW,theta,rho,P);

% % Optional: create a plot that displays the original image with the lines 
% % superimposed on it.
% figure, imshow(raster), hold on
% for k = 1:length(lines)
%    xy = [lines(k).point1; lines(k).point2];
%    plot(xy(:,1),xy(:,2),'LineWidth',2,'Color','green');
%    % waitforbuttonpress;
% 
%    % Plot beginnings and ends of lines
%    plot(xy(1,1),xy(1,2),'x','LineWidth',2,'Color','yellow');
%    plot(xy(2,1),xy(2,2),'x','LineWidth',2,'Color','red');
% 
% end

%% step 4: filter the lines generated by Hough Transform (remove colinear vectors)
% create a dummy duplicate of the list
if isempty(lines)
    disp('Data quality insufficient to determine axes! Assuming 1 axis...');
    Clusters(1).ptCloud=datapc;
    Axes=[];
    remainPc=[];
    return
end

linesDummy=lines;
j=1;

% while the duplicate still has elements...
while ~isempty(linesDummy) 
    [~,nbLines]=size(linesDummy);
    
    % take the first row as reference
    refTheta=linesDummy(1).theta;  
    refRho=linesDummy(1).rho;
    
    % create Clusters to stock the colinear lines
    ClusterName=strcat('Cluster',num2str(j));
    
    % create a struct to stock the clusters
    lines2.(ClusterName){1}=linesDummy(1);
    
    for i=2:nbLines 
        % use the subsequent rows as check
        checkTheta=linesDummy(i).theta;
        checkRho=linesDummy(i).rho;
        
        % if the difference between reference and check is less than 10
        % degrees an distance less than 10 object units, add to cluster
        if abs(refTheta-checkTheta)<10 && abs(refRho-checkRho)<10
            lines2.(ClusterName){i}=linesDummy(i);
            
            %when a row has been added to the cluster, put its values as NaN
            linesDummy(i).point1=NaN;
            linesDummy(i).point2=NaN;
            linesDummy(i).theta=NaN;
            linesDummy(i).rho=NaN;
        end
    end
    
    % put the values of the reference (1st row) as NaN
    linesDummy(1).point1=NaN;
    linesDummy(1).point2=NaN;
    linesDummy(1).theta=NaN;
    linesDummy(1).rho=NaN;
    
    % delete the struct row with NaNs
    F = @(s)any(structfun(@(a)isscalar(a)&&isnan(a),s)); % or ALL
    X = arrayfun(F,linesDummy);
    linesDummy(X) = [];
    
    % eliminate empty struct
    lines2.(ClusterName)=lines2.(ClusterName)(~cellfun('isempty',...
        lines2.(ClusterName)));
    
    % not important: transpose the result
    lines2.(ClusterName)=transpose(lines2.(ClusterName));
    j=j+1;
end
%% step 5: simplify the colinear Hough lines (merge them)
nbColinears=numel(fieldnames(lines2));
for i=1:nbColinears
    ClusterNm=string(strcat('Cluster',{num2str(i)}));
    [nbColinearEls,~]=size(lines2.(ClusterNm));
    
    %look for extremes
    listPotentialExtremes1 = zeros(nbColinearEls,2);
    listPotentialExtremes2 = zeros(nbColinearEls,2);
    for k=1:nbColinearEls
        %get a list of point 1s
        listPotentialExtremes1(k,1) = lines2.(ClusterNm){k}.point1(1);
        listPotentialExtremes1(k,2) = lines2.(ClusterNm){k}.point1(2);
        %get a list of point 2s
        listPotentialExtremes2(k,1) = lines2.(ClusterNm){k}.point2(1);
        listPotentialExtremes2(k,2) = lines2.(ClusterNm){k}.point2(2);    
    end
    %merge the list
    listPotentialExtremes=[listPotentialExtremes1;listPotentialExtremes2];
    
    %compute the centroid of these points
    centroid=[mean(listPotentialExtremes(:,1)), ...
        mean(listPotentialExtremes(:,2))];
    
    %compute the length of each node to the centroid
    for k=1:length(listPotentialExtremes)
        listPotentialExtremes(k,3)=sqrt((centroid(1)- ...
        listPotentialExtremes(k,1))^2+((centroid(2)- ...
        listPotentialExtremes(k,2))^2));
    end
    
    % take the two points located farthest from centroid as extremities
    [~, ind1] = max(listPotentialExtremes(:,3));
    listPotentialExtremes(ind1,3)      = -Inf;
    [~, ind2] = max(listPotentialExtremes(:,3));
    listPotentialExtremes(ind2,3)      = -Inf;
    
    % create a struct to store the simplified lines, taking the ind1 and
    % ind2 points as the extremities
    Vector(i).point1=listPotentialExtremes(ind1,1:2)*resolution_pix;
    Vector(i).point1(1)=Vector(i).point1(1)+minX;
    Vector(i).point1(2)=maxY-Vector(i).point1(2);
    Vector(i).point2=listPotentialExtremes(ind2,1:2)*resolution_pix;
    Vector(i).point2(1)=Vector(i).point2(1)+minX;
    Vector(i).point2(2)=maxY-Vector(i).point2(2);
    Vector(i).theta=lines2.(ClusterNm){1,1}.theta;
    Vector(i).rho=lines2.(ClusterNm){1,1}.rho;
    Vector(i).length=sqrt((Vector(i).point1(1)-Vector(i).point2(1))^2+...
        (Vector(i).point1(2)-Vector(i).point2(2))^2);
end

% % Optional: show the detected merged lines superposed on the point cloud
% figure 
% pcshow(pcTransformPCA)
% hold on
% for k = 1:length(Vector)
%    xy = [Vector(k).point1; Vector(k).point2];
%    plot3(xy(:,1),xy(:,2),[0;0],'LineWidth',2);
% end


%% step 6: determine the number of axes in the input data
i=1;

% create a duplicate of the previous structure
VectorDummy=Vector;
if isempty(Vector)
    disp('Data quality insufficient to determine axes! Assuming 1 axis...');
    Clusters(1).ptCloud=datapc;
    Axes=[];
    remainPc=[];
    return
end
Axes=[];
while ~isempty(VectorDummy) 
    %take the longest row as reference
    a=[VectorDummy.length];
    [~,idx]=max(a);
    refTheta=VectorDummy(idx).theta; 
    
    % look for rows whose theta column is similar to the reference
    fun = @(x) VectorDummy(x).theta > refTheta-5 && ...
        VectorDummy(x).theta < refTheta+5; % useful for complicated fields
    tf2 = arrayfun(fun, 1:numel(VectorDummy));
    index2 = find(tf2);
    
    % get the number of lines having the same theta direction
    [~,nbLines] = size(index2);
    
    % if there is only 1 line or more than 2, impossible to determine the
    % axe...
    if nbLines<2 || nbLines>2
         VectorDummy(idx).theta=NaN;
         
        %delete the struct row with NaNs
        F = @(s)any(structfun(@(a)isscalar(a)&&isnan(a),s)); % or ALL
        X = arrayfun(F,VectorDummy);
        VectorDummy(X) = [];
         continue
    end
    
    % the lines represent the edges of the point cloud. We want to get the
    % axe which is located at the center. Solution: averaging the two line
    % equations
    
    % first, determine the line equation components (a and b in y=ax+b)
    x1a=VectorDummy(index2(1)).point1(1);
    y1a=VectorDummy(index2(1)).point1(2);
    x2a=VectorDummy(index2(1)).point2(1);
    y2a=VectorDummy(index2(1)).point2(2);
    
    % a and b of the first line
    aa=(y1a-y2a)/(x1a-x2a);
    ba=(y2a*x1a-y1a*x2a)/(x1a-x2a);
    
    x1b=VectorDummy(index2(2)).point1(1);
    y1b=VectorDummy(index2(2)).point1(2);
    x2b=VectorDummy(index2(2)).point2(1);
    y2b=VectorDummy(index2(2)).point2(2);
    
    % a and b of the second line
    ab=(y1b-y2b)/(x1b-x2b);
    bb=(y2b*x1b-y1b*x2b)/(x1b-x2b);
    
    % put the information in a struct 'Axes'
    Axes(i).a=(aa+ab)/2;
    Axes(i).b=(ba+bb)/2;
    Axes(i).theta=VectorDummy(index2(1)).theta;
    
    % set an arbitrary first and second point for the line representing the
    % axe
    Axes(i).x1 = minX;
    Axes(i).y1 = (minX*Axes(i).a)+Axes(i).b;
    Axes(i).z1 = 0;
    Axes(i).x2 = maxX;
    Axes(i).y2 = (maxX*Axes(i).a)+Axes(i).b;
    Axes(i).z2 = 0;
    
    % when the duplicate row has been used, set one of its elements to NaN
    VectorDummy(index2(1)).theta=NaN;
    VectorDummy(index2(2)).theta=NaN;
    
    %delete the struct row with NaNs
    F = @(s)any(structfun(@(a)isscalar(a)&&isnan(a),s)); % or ALL
    X = arrayfun(F,VectorDummy);
    VectorDummy(X) = [];
    
    i=i+1;
end
if isempty(Axes)
    disp('Data quality insufficient to determine axes! Assuming 1 axis...');
    Clusters(1).ptCloud=datapc;
    remainPc=[];
    return
elseif length(Axes)==1
    disp('1 axis was found!');
    Clusters(1).ptCloud=datapc;
    remainPc=[];
    Axes=[];
    return
end
    
nbAxes = length(Axes);
disp(strcat(num2str(nbAxes),32,'axes were found!'));
% Plot the axes superposed on the (PCA-transformed) point cloud
figure 
pcshow(pcTransformPCA)
title(strcat('Number of axes found:',num2str(nbAxes)))
hold on
for k = 1:nbAxes
   plot3([Axes(k).x1;Axes(k).x2],[Axes(k).y1;Axes(k).y2],[0;0],...
       'LineWidth',2);
end

%% step 7: segment the point cloud according to the axe
% create duplicates just in case
ptCloudinput=datapc;
ptCloudinput2=pcTransformPCA;

% do a loop for each detected axe
for k=1:nbAxes
    
    % create a line with the two arbitrary points
    P = [Axes(k).x1 Axes(k).y1;Axes(k).x2 Axes(k).y2];
    
    % create a buffer zone around this line, using the width as input
    polyout1 = polybuffer(P,'lines',(beamWidth+0.2*beamWidth)/2);
    
    % check if there are points inside the buffer zone
    TFin = isinterior(polyout1,ptCloudinput2.Location(:,1), ...
        ptCloudinput2.Location(:,2));
    
    % retrieve the indices of points located inside the buffer zone
    rows = find(TFin(:,1)==1);
    
    % segment the point cloud with the inlier indices directly from the
    % original input point cloud
    ptCloudAxe=select(ptCloudinput,rows);
    
    % retrive the remaining points
    rows2 = find(TFin(:,1)==0);
    remainPcPCA=select(ptCloudinput2,rows2);
    ptCloudinput2=remainPcPCA;
    remainPc=select(ptCloudinput,rows2);
    ptCloudinput=remainPc;
    
    % create a struct containing the segmented point clouds
    Clusters(k).ptCloud=ptCloudAxe;
end

% toc
