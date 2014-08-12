%PARSEJSON parses a json string into Matlab data structures
% PARSEJSON(STRING)
%    reads STRING as JSON data, and creates Matlab data structures
%    from it.
%    - strings are converted to strings
%    - numbers are converted to doubles
%    - true, false are converted to logical 1, 0
%    - null is converted to []
%    - arrays are converted to cell arrays
%    - objects are converted to structs
%
%    In contrast to many other JSON parsers, this one does not try to
%    convert all-numeric arrays into matrices. Thus, nested data
%    structures are encoded correctly.
%
%    This is a complete implementation of the JSON spec, and invalid
%    data will generally throw errors.

% (c) 2014 Bastian Bechtold

function [obj] = parsejson(json)
    idx = next(json, 1);
    [obj, idx] = value(json, idx);
    idx = next(json, idx);
    if idx ~= length(json)+1
        error('JSON:parse:multipletoplevel', ...
              ['more than one top-level item (char ' num2str(idx) ')']);
    end
end

% advances idx to the first non-whitespace
function [idx] = next(json, idx)
    while idx <= length(json) && any(json(idx) == sprintf(' \t\r\n'))
        idx = idx+1;
    end
end

% dispatches based on JSON type
function [obj, idx] = value(json, idx)
    char = json(idx);
    if char == '"'
        [obj, idx] = string(json, idx);
    elseif any(char == '0123456789-')
        [obj, idx] = number(json, idx);
    elseif char == '{'
        [obj, idx] = object(json, idx);
    elseif char == '['
        [obj, idx] = array(json, idx);
    elseif char == 't'
        [obj, idx] = true(json, idx);
    elseif char == 'f'
        [obj, idx] = false(json, idx);
    elseif char == 'n'
        [obj, idx] = null(json, idx);
    else
        error('JSON:parse:unknowntype', ...
              ['unrecognized character "' char ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses a string and advances idx
function [obj, idx] = string(json, idx)
    obj = '';
    if json(idx) ~= '"'
        error('JSON:parse:string:noquote', ...
              ['string must start with " (char ' num2str(idx) ')']);
    end
    idx = idx+1;
    start = idx;
    stop = regexp(json(start:end), '(?<!\\)"', 'once');
    idx = start+stop;
    obj = json(start:start+stop-2);
    % check for errors
    match = regexp(obj, '\\[^trnfbu\\/"]', 'match', 'once');
    if length(match) > 0
        error('JSON:parse:string:unknownescape', ...
              ['string "' obj '" contains illegal escape sequence "' match '")']);
    end
    obj = strrep(obj, '\t', sprintf('\t'));
    obj = strrep(obj, '\r', sprintf('\r'));
    obj = strrep(obj, '\n', sprintf('\n'));
    obj = strrep(obj, '\f', sprintf('\f'));
    obj = strrep(obj, '\b', sprintf('\b'));
    obj = strrep(obj, '\/', '/');
    obj = strrep(obj, '\"', '"');
    % replace \u09af with char(hex2dec('09af'))
    matches = regexp(obj, '\\u[0-9a-f]{4}');
    for uidx=1:length(matches)
        match_idx = matches(uidx)-5*(uidx-1);
        match = char(hex2dec(obj(match_idx+2:match_idx+5)));
        if match_idx == 1
            before = '';
        else
            before = obj(1:match_idx-1);
        end
        if match_idx+5 == length(obj)
            after = '';
        else
            after = obj(match_idx+6:end);
        end
        obj = [before match after];
    end
    obj = strrep(obj, '\\', '\');
end

% parses a number and advances idx
function [obj, idx] = number(json, idx)
    start = idx;
    if getchar() == '-'
        idx = idx+1;
    end
    if getchar == '0'
        idx = idx+1;
    elseif any(getchar() == '123456789')
        idx = idx+1;
        digits();
    else
        error('JSON:parse:number:nodigit', ...
              ['number ' json(start:idx-1) ' must start with digit' ...
               '(char ' num2str(start) ')']);
    end
    if getchar() == '.'
        idx = idx+1;
        if any(getchar() == '0123456789')
            idx = idx+1;
        else
            error('JSON:parse:number:nodecimal', ...
                  ['no digit after decimal point in ' ...
                    json(start:idx-1) ' (char ' num2str(start) ')']);
        end
        digits();
    end
    if getchar() == 'e' || getchar() == 'E'
        idx = idx+1;
        if getchar() == '+' || getchar() == '-'
            idx = idx+1;
        end
        if any(getchar() == '0123456789')
            idx = idx+1;
            digits();
        else
            error('JSON:parse:number:noexponent', ...
                  ['no digit in exponent of ' json(start:idx-1) ...
                   ' (char ' num2str(start) ')']);
        end
    end
    obj = str2num(json(start:idx-1));

    function digits()
        while any(getchar() == '1234567890')
            idx = idx+1;
        end
    end

    function c = getchar()
        if idx > length(json)
            c = ' ';
        else
            c = json(idx);
        end
    end
end

% parses an object and advances idx
function [obj, idx] = object(json, idx)
    start = idx;
    obj = struct();
    if json(idx) ~= '{'
        error('JSON:parse:object:nobrace', ...
              ['object must start with "{" (char ' num2str(idx) ')']);
    end
    idx = idx+1;
    idx = next(json, idx);
    if json(idx) ~= '}'
        while 1
            [k, idx] = string(json, idx);
            idx = next(json, idx);
            if json(idx) == ':'
                idx = idx+1;
            else
                error('JSON:parse:object:nocolon', ...
                      ['no ":" after object key in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
            idx = next(json, idx);
            [v, idx] = value(json, idx);
            obj.(k) = v;
            idx = next(json, idx);
            if json(idx) == ','
                idx = idx+1;
                idx = next(json, idx);
                continue
            elseif json(idx) == '}'
                break
            else
                error('JSON:parse:object:unknownseparator', ...
                      ['no "," or "}" after entry in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
        end
    end
    idx = idx+1;
end

% parses an array and advances idx
function [obj, idx] = array(json, idx)
    start = idx;
    obj = {};
    if json(idx) ~= '['
        error('JSON:parse:array:nobracket', ...
              ['array must start with "[" (char ' num2str(idx) ')']);
    end
    idx = idx+1;
    idx = next(json, idx);
    if json(idx) ~= ']'
        while 1
            [v, idx] = value(json, idx);
            obj = [obj, {v}];
            idx = next(json, idx);
            if json(idx) == ','
                idx = idx+1;
                idx = next(json, idx);
                continue
            elseif json(idx) == ']'
                break
            else
                error('JSON:parse:array:unknownseparator', ...
                      ['no "," or "]" after entry in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
        end
    end
    idx = idx+1;
end

% parses true and advances idx
function [obj, idx] = true(json, idx)
    start = idx;
    if length(json) < idx+3
        error('JSON:parse:true:notenoughdata', ...
              ['not enough data for "true" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+3) == 'true'
        obj = logical(1);
        idx = idx+4;
    else
        error('JSON:parse:true:nottrue', ...
              ['not "true": "' json(start:idx+3) ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses false and advances idx
function [obj, idx] = false(json, idx)
    start = idx;
    if length(json) < idx+4
        error('JSON:parse:false:notenoughdata', ...
              ['not enough data for "false" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+4) == 'false'
        obj = logical(0);
        idx = idx+5;
    else
        error('JSON:parse:false:notfalse', ...
              ['not "false": "' json(start:idx+4) ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses null and advances idx
function [obj, idx] = null(json, idx)
    start = idx;
    if length(json) < idx+3
        error('JSON:parse:null:notenoughdata', ...
              ['not enough data for "null" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+3) == 'null'
        obj = [];
        idx = idx+4;
    else
        error('JSON:parse:null:notnull', ...
              ['not "null": "' json(start:idx+3) ...
               '" (char ' num2str(idx) ')']);
    end
end