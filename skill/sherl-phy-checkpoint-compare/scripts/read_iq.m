function [iq,meta]=read_iq(path,nmeta,width,lanes)
fid=fopen(path,'r');assert(fid>=0,'缺少采集文件%s',path);cleanup=onCleanup(@()fclose(fid));
c=textscan(fid,[repmat('%f ',1,nmeta) '%s %s'],'Delimiter',' ','MultipleDelimsAsOne',true);
meta=[c{1:nmeta}];count=numel(c{nmeta+1});iq=zeros(lanes,count);hex_count=width/4;
for q=0:1
    words=string(c{nmeta+1+q});values=zeros(lanes,count);
    assert(all(strlength(words)==lanes*hex_count),'采集位宽不一致：%s',path);
    for lane=1:lanes
        digits=extractBetween(words,(lanes-lane)*hex_count+1,(lanes-lane+1)*hex_count);
        value=hex2dec(digits);value(value>=2^(width-1))=value(value>=2^(width-1))-2^width;
        values(lane,:)=value.';
    end
    if q==0,iq=values;else,iq=complex(iq,values);end
end
end
