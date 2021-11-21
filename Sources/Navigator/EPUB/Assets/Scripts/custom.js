var CFI_REGEX = /(.+)#(\w+)\(([\d\/]+):(\d+)\)/;
var START_TAG = '<span class="readiumCSS-yellow-highlight">';
var END_TAG = '</span>';
var ELEMENTS;

function getDescendants(acc, el){
  acc.push(el);
  if(el.children.length) {
    return Array.from(el.children).reduce(getDescendants, acc);
  } else {
    return acc;
  }
}

function getElementsBetween(startEl, endEl) {
  return ELEMENTS.slice(ELEMENTS.indexOf(startEl), ELEMENTS.indexOf(endEl) + 1);
}

function getNthChildElement(el, index) {
  return el.children[index / 2 - 1];
}

function getElementFromIndexPath(path) {
  try {
    return path.reduce(getNthChildElement, document.documentElement);
  } catch(error) {
    console.log('No element found at path:', path.join('/'));
    return null;
  }
}

function parseCFI(cfi) {
  var match = cfi.match(CFI_REGEX);
  if(!match) {
    console.log('Incorrectly formatted CFI:', cfi);
    return null;
  }

  return {
    'filename': match[1],
    'scheme': match[2],
    'rawPath': match[3],
    'path': match[3]
    .split('/')
    .map(function(val) { return parseInt(val); })
    .filter(function(val) { return val > 1 }),
    'offset': parseInt(match[4])
  };
}

function insertTags(html, o1, o2, t1, t2) {
  return html.slice(0, o1) + t1 + html.slice(o1, o2) + t2 + html.slice(o2);
}

function placeHighlight(highlight) {
  console.log(highlight);
  var start, end, startEl, endEl, els;
  start = parseCFI(highlight.start);
  end = parseCFI(highlight.end);
  if(!start || !end) {
    return;
  }
  startEl = getElementFromIndexPath(start.path);
  endEl = getElementFromIndexPath(end.path);
  if(!startEl || !endEl) {
    return;
  }
  els = getElementsBetween(startEl, endEl);
  els.forEach(function(el, index) {
    el.innerHTML = insertTags(
      el.innerHTML,
      index == 0 ? start.offset : 0,
      index == els.length - 1 ? end.offset : el.innerHTML.length,
      START_TAG,
      END_TAG
    );
  });
}
                  
function removeHighlights() {
  var spans = document.getElementsByClassName("readiumCSS-yellow-highlight");
  for(var i=0; i<spans.length;i++) {
    spans[i]. outerHTML = spans[i]. innerHTML;
  }
}

ELEMENTS = getDescendants([], document.body);

// TODO: does not handle overlapping highlights well
