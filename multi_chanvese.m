%%%%% multi-chanvese %%%%%%
function [seg,phi,its] = multi_chanvese(I,init_mask,kai,sz,max_its,alpha,thresh,display)

%-- default value for parameter alpha is .1
    if(~exist('alpha','var')) 
        alpha = .2; 
    end
    %-- default value for parameter thresh is 0
    if(~exist('thresh','var')) 
        thresh = 0; 
    end            
    %-- default behavior is to display intermediate outputs
    if(~exist('display','var'))
        display = true;
    end
    color='r';
    %-- ensures image is 2D double matrix
    I = im2graydouble(I);    
    
    %-- Create a signed distance map (SDF) from mask
    phi = mask2phi(init_mask);
    
    %--main loop
    its = 0;      stop = 0;
    prev_mask = init_mask;        c = 0;
    nbr=[1,1;1,0;1,-1;0,1;0,-1;-1,1;-1,0;-1,-1];
    NB_width=1.2; %%%% increment by 0.2
    increa = 0.2;
    epsilon_merge = 0.001;
    [dimx,dimy]=size(kai);
    phi_temp=zeros(dimx,dimy);
    numObj = uint16(max(kai(:)));
    se2= strel('disk',2);
      
    while ((its < max_its) && ~stop)
    
        idx = find(phi < NB_width & phi > -NB_width); % get the curve's narrow band
        num_idx = numel(idx);
        if ~isempty(idx)
            %-- intermediate output
            if (display>0)
                          
                    showCurveAndPhi(phi,I,color);
                    title([num2str(its),'  iteration']);
                    drawnow
%                 if ( mod(its,5)==1 )  
%                     keyboard
%                 end
                
            end

            %-- find interior and exterior mean           
            %upts = find(phi<=0);                 % interior points
            vpts = find(phi>0);                  % exterior points
            %u = sum(I(upts))/(length(upts)+eps); % interior mean
            v = sum(I(vpts))/(length(vpts)+eps); % exterior mean

            %F = (I(idx)-u).^2-(I(idx)-v).^2;     % force from image information
            curvature = get_curvature(phi,idx);  % force from curvature penalty

            %dphidt = F./max(abs(F)) + alpha*curvature;  % gradient descent to minimize energy
            if(its==20)
                keyboard
            end
            dphidt=zeros(1,num_idx);
            %F=zeros(1,num_idx);
            %regularTerm=zeros(1,num_idx);
            for obj_iter = 1:1:numObj
                upts = (kai==obj_iter);
                tmp_sz = nnz(upts);
                u=sum(I(upts))/(tmp_sz+eps);
                imgk = imdilate(upts,se2);
                tmp = find(imgk(idx)>0);
                F=(I(idx(tmp))-u).^2 - (I(idx(tmp))-v).^2;
                regularTerm=zeros(numel(tmp),1);
                if(tmp_sz<sz(obj_iter)*0.75)  
                    regularTerm(:,1)=alpha*curvature(tmp)-0.1/(1+exp(10*tmp_sz/sz(obj_iter)-8.5));
                elseif(tmp_sz>sz(obj_iter)*1.25)
                    regularTerm(:,1)=alpha*curvature(tmp)+0.1/(1+exp(-10*tmp_sz/sz(obj_iter)+11.5));
                end
                try
                dphidt(tmp)=F./max(abs(F))+regularTerm;
                catch
                    keyboard
                end
            end
            
            %-- maintain the CFL condition
            dt = .45/(max(abs(dphidt))+eps);

            %-- evolve the curve        
            %phi(idx) = phi(idx) +  dt.*dphidt;
            phi_temp(idx) = dt.*dphidt;
          
            %%%% extract narrow band points iteratively%%%%
            for bd_iter = increa:increa:NB_width
                nb = find((phi<bd_iter & phi>=bd_iter-increa) | (phi>-bd_iter  & phi<=-bd_iter+increa));              
                num_nb = numel(nb);
                if(num_nb==0)
                    continue;
                end
                [nbx,nby]=ind2sub([dimx,dimy],nb);
                for i=1:1:num_nb
                    tx=nbx(i);ty=nby(i);
                    if(phi(tx,ty)>0 && phi_temp(tx,ty)<=0)
                        
                        a=kai(max(tx-1,1):1:min(tx+1,dimx),max(ty-1,1):1:min(ty+1,dimy));
                        a(2,2)=0;
                        tmp_obj=unique(nonzeros(a));
                        On=numel(tmp_obj);
                        if(On==1)
                            kai(tx,ty)=tmp_obj;
                            phi(tx,ty)=phi_temp(tx,ty);
                            continue;
                        end
                        
                        if(On==0)
                            phi(tx,ty)=epsilon_merge;
                            continue;
                            %disp('expanding to an isolated point');
                            %keyboard
                        end
                        
                        a(2,2)=1;
                        b=(a==0);
                        cc=bwconncomp(b,8);
                        if(cc.NumObjects~=1)
                            phi(tx,ty)=epsilon_merge;
                            continue;
                        end
                        
                        a(2,2)=0;
                        b=(a>0);
                        cc=bwconncomp(b,4);
                        if(cc.NumObjects~=1) %%% not simple
                            phi(tx,ty)=epsilon_merge;
                            continue;
                        end

                        kai(tx,ty)=tmp_obj(1);
                        phi(tx,ty)=phi_temp(tx,ty);
                        
                       
                    elseif(phi(tx,ty)<=0 && phi_temp(tx,ty)>0)
                        a=kai(max(tx-1,1):1:min(tx+1,dimx),max(ty-1,1):1:min(ty+1,dimy));
                        a(2,2)=0;
                        tmp_obj=unique(nonzeros(a));
    
                        if(numel(tmp_obj)>1)
                            disp('unexpected touching');
                            keyboard;
                        elseif(numel(tmp_obj)==0)
                            disp('isolated point');
                            keyboard
                        end
                        
                        b=(a>0);
                        cc=bwconncomp(b,4);
                        if(cc.NumObjects~=1) %%% not simple
                            phi(tx,ty)=-epsilon_merge;
                            continue;
                        end
                        
                        a(2,2)=1;
                        b=(a==0);
                        cc=bwconncomp(b,8);
                        if(cc.NumObjects~=1)
                            phi(tx,ty)=-epsilon_merge;
                            continue;
                        end
                        
                        phi(tx,ty)=phi_temp(tx,ty);
                        kai(tx,ty)=0;
                    else
                        phi(tx,ty)=phi_temp(tx,ty);
                    end
                end
            end

            %-- Keep SDF smooth
            phi = sussman(phi, .5);
            
            new_mask = phi<=0;
            c = convergence(prev_mask,new_mask,thresh,c);
            if c <= 5
                its = its + 1;
                prev_mask = new_mask;
            else stop = 1;
            end      

        else
            break;
        end    
    end

    %-- final output
    showCurveAndPhi(phi,I,color); 
    title([num2str(its),'  iteration']);
    drawnow

    %-- make mask from SDF
    seg = phi<=0; %-- Get mask from levelset
  
%---------------------------------------------------------------------
%-- AUXILIARY FUNCTIONS ----------------------------------------------
%---------------------------------------------------------------------
 
%-- Displays the image with curve superimposed
function showCurveAndPhi(phi,I,cl)

    figure(2);
    imagesc(I,[0, 255]); axis off; axis equal; colormap(gray); 
	hold on; contour(phi,[0 0],cl,'Linewidth',1); hold off;
% 	delete(h);
%     test = isequal(size(c,2),0);
% 	while (test==false)
%         s = c(2,1);
%         if ( s == (size(c,2)-1) )
%             t = c;
%             figure(1)
%             hold on; plot(t(1,2:end)',t(2,2:end)',cl,'Linewidth',3);
%             test = true;
%         else
%             t = c(:,2:s+1);
%             figure(1)
%             hold on; plot(t(1,1:end)',t(2,1:end)',cl,'Linewidth',3);
%             c = c(:,s+2:end);
%         end
% 	end    
  
  
%-- converts a mask to a SDF
function phi = mask2phi(init_a)
    phi=bwdist(init_a)-bwdist(1-init_a)+im2double(init_a)-.5;
  
%-- compute curvature along SDF
function curvature = get_curvature(phi,idx)
    [dimy, dimx] = size(phi);        
    [y x] = ind2sub([dimy,dimx],idx);  % get subscripts

    %-- get subscripts of neighbors
    ym1 = y-1; xm1 = x-1; yp1 = y+1; xp1 = x+1;

    %-- bounds checking  
    ym1(ym1<1) = 1; xm1(xm1<1) = 1;              
    yp1(yp1>dimy)=dimy; xp1(xp1>dimx) = dimx;    

    %-- get indexes for 8 neighbors
    idup = sub2ind(size(phi),yp1,x);    
    iddn = sub2ind(size(phi),ym1,x);
    idlt = sub2ind(size(phi),y,xm1);
    idrt = sub2ind(size(phi),y,xp1);
    idul = sub2ind(size(phi),yp1,xm1);
    idur = sub2ind(size(phi),yp1,xp1);
    iddl = sub2ind(size(phi),ym1,xm1);
    iddr = sub2ind(size(phi),ym1,xp1);
    
    %-- get central derivatives of SDF at x,y
    phi_x  = -phi(idlt)+phi(idrt);
    phi_y  = -phi(iddn)+phi(idup);
    phi_xx = phi(idlt)-2*phi(idx)+phi(idrt);
    phi_yy = phi(iddn)-2*phi(idx)+phi(idup);
    phi_xy = -0.25*phi(iddl)-0.25*phi(idur)...
             +0.25*phi(iddr)+0.25*phi(idul);
    phi_x2 = phi_x.^2;
    phi_y2 = phi_y.^2;
    
    %-- compute curvature (Kappa)
    curvature = ((phi_x2.*phi_yy + phi_y2.*phi_xx - 2*phi_x.*phi_y.*phi_xy)./...
              (phi_x2 + phi_y2 +eps).^(3/2)).*(phi_x2 + phi_y2).^(1/2);        
  
%-- Converts image to one channel (grayscale) double
function img = im2graydouble(img)    
    [dimy, dimx, c] = size(img);
    if(isfloat(img)) % image is a double
        if(c==3) 
            img = rgb2gray(uint8(img)); 
        end
    else           % image is a int
        if(c==3) 
            img = rgb2gray(img); 
        end
        img = double(img);
    end

%-- level set re-initialization by the sussman method
function D = sussman(D, dt)
    % forward/backward differences
    a = D - shiftR(D); % backward
    b = shiftL(D) - D; % forward
    c = D - shiftD(D); % backward
    d = shiftU(D) - D; % forward

    a_p = a;  a_n = a; % a+ and a-
    b_p = b;  b_n = b;
    c_p = c;  c_n = c;
    d_p = d;  d_n = d;

    a_p(a < 0) = 0;
    a_n(a > 0) = 0;
    b_p(b < 0) = 0;
    b_n(b > 0) = 0;
    c_p(c < 0) = 0;
    c_n(c > 0) = 0;
    d_p(d < 0) = 0;
    d_n(d > 0) = 0;

    dD = zeros(size(D));
    D_neg_ind = find(D < 0);
    D_pos_ind = find(D > 0);
    dD(D_pos_ind) = sqrt(max(a_p(D_pos_ind).^2, b_n(D_pos_ind).^2) ...
                       + max(c_p(D_pos_ind).^2, d_n(D_pos_ind).^2)) - 1;
    dD(D_neg_ind) = sqrt(max(a_n(D_neg_ind).^2, b_p(D_neg_ind).^2) ...
                       + max(c_n(D_neg_ind).^2, d_p(D_neg_ind).^2)) - 1;

    D = D - dt .* sussman_sign(D) .* dD;
  
%-- whole matrix derivatives
function shift = shiftD(M)
    shift = shiftR(M')';

function shift = shiftL(M)
    shift = [ M(:,2:size(M,2)) M(:,size(M,2)) ];

function shift = shiftR(M)
    shift = [ M(:,1) M(:,1:size(M,2)-1) ];

function shift = shiftU(M)
    shift = shiftL(M')';
  
function S = sussman_sign(D)
    S = D ./ sqrt(D.^2 + 1);    

% Convergence Test
function c = convergence(p_mask,n_mask,thresh,c)
    diff = p_mask - n_mask;
    n_diff = sum(abs(diff(:)));
    if n_diff < thresh
        c = c + 1;
    else
        c = 0;
    end
