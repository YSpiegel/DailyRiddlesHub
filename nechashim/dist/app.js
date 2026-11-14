const solutions = [
 {word:'פירותהקיץ',path:[[3,0],[2,0],[2,1],[3,1],[3,2],[3,3],[3,4],[2,4],[2,5]],special:true},
 {word:'דובדבן',path:[[3,5],[4,5],[5,4],[4,4],[5,3],[4,2]]},
 {word:'אבטיח',path:[[4,3],[5,2],[4,1],[5,0],[6,1]]},
 {word:'אפרסק',path:[[4,0],[5,1],[6,2],[6,3],[7,4]]},
 {word:'ענבים',path:[[7,3],[6,4],[7,5],[6,5],[5,5]]},
 {word:'מלון',path:[[7,2],[7,1],[7,0],[6,0]]},
 {word:'משמש',path:[[0,0],[1,1],[1,2],[2,3]]},
 {word:'שזיף',path:[[1,0],[0,1],[0,2],[0,3]]},
 {word:'תות',path:[[2,2],[1,3],[0,4]]},
 {word:'אגס',path:[[1,4],[0,5],[1,5]]}
];
const key=([r,c])=>r*6+c;
solutions.forEach(s=>s.ids=s.path.map(key));
const letters=Array(48); solutions.forEach(s=>s.ids.forEach((id,i)=>letters[id]=s.word[i]));
const board=document.querySelector('#board'), lines=document.querySelector('#lines'), current=document.querySelector('#current'), message=document.querySelector('#message');
let selected=[], found=[], hint=null, dragging=false, moved=false;
try {const saved=JSON.parse(localStorage.getItem('nechashim-demo-v1')||'[]'); if(Array.isArray(saved)) found=saved.filter((x,i)=>Number.isInteger(x)&&x>=0&&x<solutions.length&&saved.indexOf(x)===i);} catch(e) {}
letters.forEach((letter,id)=>{const cell=document.createElement('button');cell.className='cell';cell.type='button';cell.textContent=letter;cell.dataset.id=id;cell.setAttribute('aria-label',`שורה ${Math.floor(id/6)+1}, עמודה ${id%6+1}, ${letter}`);board.appendChild(cell)});
function draw(){
 const used=new Map(); found.forEach(i=>solutions[i].ids.forEach(id=>used.set(id,solutions[i].special)));
 document.querySelectorAll('.cell').forEach((cell,id)=>{cell.classList.toggle('selected',selected.includes(id));cell.classList.toggle('found',used.has(id));cell.classList.toggle('special',used.get(id)===true);cell.classList.toggle('hinted',hint===id);cell.setAttribute('aria-pressed',selected.includes(id));});
 lines.innerHTML=''; const line=(ids,color)=>{if(ids.length<2)return;const poly=document.createElementNS('http://www.w3.org/2000/svg','polyline');poly.setAttribute('points',ids.map(id=>`${(id%6)*100+50},${Math.floor(id/6)*100+50}`).join(' '));poly.setAttribute('fill','none');poly.setAttribute('stroke',color);poly.setAttribute('stroke-width','35');poly.setAttribute('stroke-linecap','round');poly.setAttribute('stroke-linejoin','round');lines.appendChild(poly)};
 found.forEach(i=>line(solutions[i].ids,solutions[i].special?'#f3d77f':'#dbecc7'));line(selected,'#c6e29c');
 current.textContent=selected.length?selected.map(i=>letters[i]).join(''):'בחרו אות כדי להתחיל';current.classList.toggle('active',selected.length>0);document.querySelector('#submit').disabled=!selected.length;
 document.querySelector('#count').textContent=`${found.length} / ${solutions.length}`;document.querySelector('#progressBar').style.width=`${found.length/solutions.length*100}%`;document.querySelector('#progressText').textContent=found.length===solutions.length?'כל הכבוד!':found.length?'ממשיכים לגלות':'יוצאים לדרך!';
 const list=document.querySelector('#found');list.replaceChildren();if(!found.length){const empty=document.createElement('span');empty.className='empty';empty.textContent='כאן יופיעו המילים שמצאתם';list.appendChild(empty)}found.forEach(i=>{const chip=document.createElement('span');chip.className='chip'+(solutions[i].special?' special-chip':'');chip.textContent=(solutions[i].special?'✦ ':'')+(solutions[i].special?'פירות הקיץ':solutions[i].word);list.appendChild(chip)});
}
function add(id){if(found.some(i=>solutions[i].ids.includes(id)))return; if(selected.at(-1)===id){selected.pop();draw();return} if(selected.includes(id))return;const prev=selected.at(-1);if(prev!==undefined&&(Math.abs(Math.floor(prev/6)-Math.floor(id/6))>1||Math.abs(prev%6-id%6)>1))return;selected.push(id);hint=null;draw()}
function submit(){if(!selected.length)return;const match=solutions.findIndex((s,i)=>!found.includes(i)&&s.ids.length===selected.length&&s.ids.every((id,j)=>id===selected[j]));if(match>=0){found.push(match);try{localStorage.setItem('nechashim-demo-v1',JSON.stringify(found))}catch(e){} message.textContent=found.length===solutions.length?'מצאתם את כולן! איזו חגיגה ☀':solutions[match].special?'מילת הנושא נמצאה! ✦':'יש! מצאתם מילה ששייכת לנושא';}else{message.textContent='לא הפעם — נסו מסלול אחר';}selected=[];draw()}
board.addEventListener('pointerdown',e=>{const cell=e.target.closest('.cell');if(!cell)return;e.preventDefault();dragging=true;moved=false;board.setPointerCapture(e.pointerId);add(Number(cell.dataset.id))});board.addEventListener('pointermove',e=>{if(!dragging)return;const cell=document.elementFromPoint(e.clientX,e.clientY)?.closest('.cell');if(cell&&Number(cell.dataset.id)!==selected.at(-1)){const before=selected.length;add(Number(cell.dataset.id));if(selected.length!==before)moved=true}});board.addEventListener('pointerup',()=>{if(dragging&&moved)submit();dragging=false});board.addEventListener('pointercancel',()=>{dragging=false});
board.addEventListener('click',e=>{if(e.detail===0){const cell=e.target.closest('.cell');if(cell)add(Number(cell.dataset.id))}});document.querySelector('#submit').onclick=submit;
document.querySelector('#hintBtn').onclick=()=>{const next=solutions.find((s,i)=>!found.includes(i));if(!next){message.textContent='כבר מצאתם את כל המילים!';return}hint=next.ids[0];selected=[];message.textContent='סימנו את האות הראשונה של מילה שטרם נמצאה';draw()};
document.querySelector('#resetBtn').onclick=()=>{if(!confirm('להתחיל את החידה מחדש?'))return;found=[];selected=[];hint=null;try{localStorage.removeItem('nechashim-demo-v1')}catch(e){}message.textContent='אפשר גם לגרור בין האותיות';draw()};
const dialog=document.querySelector('#help');document.querySelector('#helpBtn').onclick=()=>dialog.showModal();document.querySelectorAll('.close,.close-dialog').forEach(b=>b.onclick=()=>dialog.close());draw();
