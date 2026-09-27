/* Copyright 2026 B&A community. Apache-2.0. */
const translations={
 'Live скругление':'Live bevel','Размер, мм':'Size, mm','Сегментов':'Segments',
 'Отступ / катет':'Edge offset','Радиус':'Radius','Указать мышью':'Pick offset',
 'Отображение':'Display','Исходник':'Proxy','Скругление':'Bevel','Исходник + скругление':'Both',
 'Непрозрачность результата':'Surface opacity','Сглаживать границы скругления':'Smooth bevel borders',
 'Редактировать исходник':'Edit proxy','Снять Live':'Remove Live','Запечь':'Commit',
 'Сглаживание рёбер':'Soften edges','Порог угла, °':'Angle threshold, °',
 'Сглаживать мягкие рёбра':'Smooth soft edges','Сообщать результат обработки':'Show operation notifications',
 'Язык интерфейса':'Interface language','Показать':'Show','Применить':'Apply','Катет':'Offset',
 'Сохранять исходник (параметрическая фаска)':'Keep source (parametric bevel)',
 'Запечь фаску':'Bake bevel','Скрыть':'Hide'
};
window.setLanguage=function(lang){
 document.documentElement.lang=lang;
 const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT), nodes=[];
 while(walker.nextNode())nodes.push(walker.currentNode);
 for(const node of nodes){const original=node._ru||(node._ru=node.textContent), trimmed=original.trim();if(translations[trimmed])node.textContent=lang==='en'?original.replace(trimmed,translations[trimmed]):original;}
};
