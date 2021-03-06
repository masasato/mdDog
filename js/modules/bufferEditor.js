'use strict'

define(function(){
    var bufferEditor = function(){};
    bufferEditor.prototype = {
        init: function(){
            this.movableMenu();

            require(['commitForm'], function(CommitForm){
                new CommitForm().init();
            });
            
            if($('body > section.MdBuffer .BufferEdit').length){
                require(['mdBufferEditor'], function(MdBufferEditor){
                    new MdBufferEditor().init();
                });
            }
        },

        movableMenu: function(){
            var off     = $('.BufferEditMenu').offset();
            var menuFlg = false;
            $(window).scroll($.proxy(function(){
                var p = $(window).scrollTop();
                if( !menuFlg && p >= off.top ){
                    menuFlg = this.toggleMenu(menuFlg);
                }else if( menuFlg && p < off.top ){
                    menuFlg = this.toggleMenu(menuFlg);
                }
            }, this));
        },

        toggleMenu: function(flg){
            if(flg){
                $('.BufferEditMenu').css({
                    "position": "absolute",
                    "top": "auto"
                }); 
            }else{
                $('.BufferEditMenu').css({
                    "position": "fixed",
                    "top": "0"
                }); 
            }
            return !flg;
        }
    };

    return bufferEditor;
});
