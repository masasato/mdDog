'use strict'
/*
 * バッファ編集エディタのアウトライン分割制御クラス
 */

define(function(){
    var divideCtrl = function() {
        this.activeIndex = 0;
    };
    divideCtrl.prototype = {
        init: function (){
            var divide = [];
            $('.MdBuffer  ul.Pagenav').find('a.OutlinePage').each($.proxy(function(index, obj){
                divide.push($(obj).data('elm'));
                $(obj).data('id', index);
                $(obj).click($.proxy(function(ev){
                    var id = Number($(ev.target).data('id'));
                    if(id === this.activeIndex){
                        return;
                    }

                    $('.MdBuffer .Document .Md').hide();
                    $('.MdBuffer .Document .Editform').remove();
	                this.showPage(divide, id);
	                this.activeNum(id);
                    this.activeIndex = id;
                }, this));
            }, this));
            this.showPage(divide, this.activeIndex);
            this.activeNum(this.activeIndex);
        },

        showPage: function(dividesAr, id){
            var tmp = undefined;
            for(var i=0; i < dividesAr.length; i++) 
            {
                if( i === id ){
                    tmp = dividesAr[i];
                }else{
                    if( tmp !== undefined ){
                        for(var j=tmp; j < dividesAr[i]; j++){
                            $('#md' + j).show();
                        }
                        tmp = undefined;
                    }
                }
            }
            if( tmp !== undefined ){
                $('.MdBuffer .Document').find('.Md').each(function(){
                    var objId = $(this).attr('id').substr(2);
                    if( objId >= tmp ){
                        $(this).show();
                    }
                });
            }
        },

        activeNum: function(num){
            $('.MdBuffer ul.Pagenav').find('a.OutlinePage').each(function(index){
                if( index === num ){
                    $(this).addClass('Active');
                }else{
                    $(this).removeClass('Active');
                }
            });
        }
    };

    return divideCtrl;
});
