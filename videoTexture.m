% Implementation of Video Textures
% http://www.cc.gatech.edu/cpl/projects/videotexture/SIGGRAPH2000/videotex.pdf

% OPTIONS %%%%%%%%%%%%%%%%%%%%%%%%
INPUT_STRING = 'clock.mpg';       % Input video name
OUTPUT_STRING = 'test.avi';  % Output video name

% Algorithm settings
IS_GIF = false;
RANDOM_PLAY = false;
VIDEO_LOOPS = true;
PRESERVE_MOTION = true;
PRUNE = true;

% Parameters
NEIGHBORS = 2;
SIGMA_MULTIPLE = .05;
OUTPUT_LENGTH_FACTOR = 3;

OUTPUT_ROW = 240;
OUTPUT_COL = 240;

% colormap gray;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Find number of frames
if IS_GIF
  % Convert gif to avi
  [img, map] = imread(INPUT_STRING);
  size(img);
  [OUTPUT_ROW, OUTPUT_COL, ~, numFrames] = size(img);
  
  totalPixels = OUTPUT_COL * OUTPUT_ROW * 3;
  videoFrames = zeros(numFrames, totalPixels);
  if ~isempty(map)
    for i = 1:numFrames
      frame = ind2rgb(img(:,:,:,i),map);
      videoFrames(i,:) = reshape(double(frame), totalPixels, 1);
    end
  end
else
  % Reads in a video
  videoStream = VideoReader(INPUT_STRING);
  numFrames = 0; i = 1;
  
  while hasFrame(videoStream)
    f = readFrame(videoStream);
    numFrames = numFrames + 1;
  end
  
  [OUTPUT_ROW, OUTPUT_COL, ~] = size(f);
  videoFrames = zeros(numFrames, OUTPUT_ROW*OUTPUT_COL*3);
  videoStream = VideoReader(INPUT_STRING);
  
  while hasFrame(videoStream)
    videoFrames(i, :) = reshape(double(readFrame(videoStream)),...
      OUTPUT_ROW*OUTPUT_COL*3, 1);
    i = i + 1;
  end
end

'found number of frames'

%% Construct D, the distance matrix
D = dist2(videoFrames, videoFrames);
D = circshift(D, [0 1]);

'made D'

%% Preserve dynamics by filtering D
if PRESERVE_MOTION
  % Weight neighboring frames to preserve continuous motion
  W_len = NEIGHBORS * 2;
  W = zeros(1, W_len);
  
  % Binomial coefficient weights
  for i = 1:W_len
    W(i) = nchoosek(W_len, i - 1);
  end
  
  W = diag(W);
  D = imfilter(D, W);
  
  [h, w] = size(D);
  D = D(NEIGHBORS:h - NEIGHBORS, NEIGHBORS:w - NEIGHBORS);
end

'preserved dynamics'

%% Construct P
% Smaller values of sigma emphasize just the very best
% transitions, while larger values of sigma allow for
% greater variety at the cost of poorer transitions.
sigma = (sum(nonzeros(D)) ./ nnz(D)) * SIGMA_MULTIPLE;

% Probabilities of jumping from frame i to j
P = exp(-D ./ sigma);

% Normalize probabilities across i so sum of Pij = 1 for all j
sumRows = sum(P, 2);
P = P ./ repmat(sumRows, 1, size(P, 2));

'made P'
%% Write out the video texture
videoOut = VideoWriter(OUTPUT_STRING);
open(videoOut);
totalFrames = numFrames * OUTPUT_LENGTH_FACTOR;
countFrames = 0;

if RANDOM_PLAY
  curIndex = 1;
  while countFrames < totalFrames
    %     curIndex
    %     imshow(reshape((videoFrames(curIndex, :)), ...
    %                OUTPUT_ROW, OUTPUT_COL, 3));
    curFrame = reshape(uint8(videoFrames(curIndex, :)), ...
      OUTPUT_ROW, OUTPUT_COL, 3);
    writeVideo(videoOut, curFrame);
    curIndex = discretesample(P(curIndex, :), 1);
    countFrames = countFrames + 1;
  end
  ' done with radom play'
elseif VIDEO_LOOPS
  
  if PRUNE
    prune = tril(-D); % Need to find the "smallest" D value with max func so need to negate it
    prune = prune - min(min(prune));
    localMinFinder = vision.LocalMaximaFinder;
    localMinFinder.MaximumNumLocalMaxima = ceil(max(max(prune)));
    localMinFinder.NeighborhoodSize = [11 11];
    localMinFinder.Threshold = max(max(prune)) * .5;
    
    IDX = step(localMinFinder, prune);
    size(IDX, 1);
  end
  
  'done with pruning'
  
  IDX = double(sort(IDX, 2, 'descend')'); % this may be a problem
  
  % Remove primitive loops that are close to the diagonal
  test = IDX(1,:) - IDX(2,:);
  test = logical(test - 1);
  IDX = IDX .* repmat(test, 2,1);
  IDX = nonzeros(IDX);
  IDX = reshape(IDX, 2, size(IDX, 1)/2);
  
  videoLoop = findVideoLoop(D, IDX, totalFrames, numFrames);
  
  'found video loop'
  
  % videoLoop = [7 38 20 25 7 40 7 40 7 40];
  videoLoop = schedule(videoLoop);
  
  'scheduled the loop'
  
  videoLoop = uint8(videoLoop); % this is scary!!
  curFrameIdx = videoLoop(2, 1);
  
  for i = 1:size(videoLoop, 2)
    curLoop = videoLoop(:, i);
    
    % Loop to the next start
    while curFrameIdx <= curLoop(2)
      curFrame = reshape(uint8(videoFrames(curFrameIdx, :)), ...
        OUTPUT_ROW, OUTPUT_COL, 3);
      writeVideo(videoOut, curFrame);
      curFrameIdx = curFrameIdx + 1;
    end
    
    % Jump to the start
    curFrameIdx = curLoop(1);
    
    % Loop to the end
    while curFrameIdx <= curLoop(2)
      curFrame = reshape(uint8(videoFrames(curFrameIdx, :)), ...
        OUTPUT_ROW, OUTPUT_COL, 3);
      writeVideo(videoOut, curFrame);
      curFrameIdx = curFrameIdx + 1;
    end
    
    % Go back to start frame
    curFrameIdx = curLoop(1);
  end
  
  'wrote video'
end

close(videoOut);
