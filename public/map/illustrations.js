const addIllustration=(selector,file,label,className)=>{const target=document.querySelector(selector);if(!target||target.querySelector(`.${className}`))return;const image=document.createElement('img');image.className=`barrio-illustration ${className}`;image.src=`assets/illustrations/${file}`;image.alt=label;target.append(image)};
addIllustration('.map-view','mapa-tianguis.png','Ilustración de mapa y tianguis','art-map');
addIllustration('.section-intro','productos.png','Ilustración de productos locales','art-products');
addIllustration('.merchant-top','comerciante.png','Ilustración de comerciante BARRIO','art-merchant');
addIllustration('.city-header','actividad-economica.png','Ilustración de actividad económica','art-intelligence');
addIllustration('.onboarding-strip','comunidad.png','Ilustración de comunidad BARRIO','art-community');
